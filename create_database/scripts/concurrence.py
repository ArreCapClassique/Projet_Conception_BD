# -*- coding: utf-8 -*-
"""
Weekly loader for Avis FR 'Le tarif de location' into Oracle table S4_AVIS.

Target schema:
CREATE TABLE S4_AVIS (
  Cat       VARCHAR2(30) NOT NULL,
  Type      VARCHAR2(30),
  Places    VARCHAR2(30),
  Energy    VARCHAR2(30),
  PrixJour  NUMBER(8,2) CHECK (PrixJour > 0),
  PrixKm    NUMBER(8,2) CHECK (PrixKm > 0),
  ValidFrom DATE
);

Set environment (edit below): ORA_HOST, ORA_PORT, ORA_SERVICE, ORA_USER, ORA_PASSWORD
"""

import re
import io
import sys
import datetime as dt
import requests
import pandas as pd

# ============ CONFIG ============

PDF_LANDING_URL = "https://docs.abgcarrental.com/pricing/avis/FR/fr"

# --- Oracle connection (edit these) ---
ORA_HOST = "127.0.0.1"
ORA_PORT = 1550
ORA_SERVICE = "siip"
ORA_USER = "BOCHENSOHANDSOME"
ORA_PASSWORD = "BOCHENSOHANDSOME"

TARGET_TABLE = "S4_AVIS"

USE_CAMELOT = True

# ============ HELPERS ============


def normalize_amount_eur(s: str):
    if s is None:
        return None
    s = (
        s.strip()
        .replace("€", "")
        .replace("EUR", "")
        .replace("\u202f", "")
        .replace(" ", "")
        .replace(",", ".")
    )
    s = re.sub(r"[^\d\.]", "", s)
    return float(s) if s else None


def session_with_headers() -> requests.Session:
    s = requests.Session()
    s.headers.update(
        {
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/120.0.0.0 Safari/537.36"
            ),
            "Accept": "application/pdf,application/xhtml+xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "fr-FR,fr;q=0.9,en-US;q=0.8,en;q=0.7",
            "Referer": "https://www.avis.fr/",
        }
    )
    return s


def get_pdf_bytes(url: str) -> bytes:
    s = session_with_headers()
    r = s.get(url, allow_redirects=True, timeout=60)
    ctype = r.headers.get("Content-Type", "").lower()
    if r.status_code == 200 and "pdf" in ctype:
        return r.content
    # Landing HTML -> find the real .pdf
    html = r.text
    m = re.search(r'href=["\']([^"\']+\.pdf[^"\']*)["\']', html, re.I)
    if not m:
        raise RuntimeError("Could not find direct PDF link on landing page.")
    pdf_url = m.group(1)
    if pdf_url.startswith("/"):
        from urllib.parse import urljoin

        pdf_url = urljoin(url, pdf_url)
    r2 = s.get(pdf_url, allow_redirects=True, timeout=60)
    r2.raise_for_status()
    return r2.content


def read_full_text(pdf_bytes: bytes) -> str:
    import pdfplumber

    out = []
    with pdfplumber.open(io.BytesIO(pdf_bytes)) as pdf:
        for page in pdf.pages:
            txt = page.extract_text() or ""
            txt = re.sub(r"[ \t]+", " ", txt).replace("\u00a0", " ")
            out.append(txt)
    return "\n".join(out)


def extract_version_date_fr(full_text: str) -> str:
    # e.g. "Prix maxima conseillés au 13 janvier 2025"
    m = re.search(
        r"Prix\s+maxima\s+conseill[ée]s\s+au\s+(\d{1,2}\s+\w+\s+\d{4})", full_text, re.I
    )
    return m.group(1) if m else ""


def version_to_iso(datestr: str) -> str:
    """
    '13 janvier 2025' -> '2025-01-13'; '' if parsing fails.
    """
    months = {
        "janvier": "01",
        "février": "02",
        "fevrier": "02",
        "mars": "03",
        "avril": "04",
        "mai": "05",
        "juin": "06",
        "juillet": "07",
        "août": "08",
        "aout": "08",
        "septembre": "09",
        "octobre": "10",
        "novembre": "11",
        "décembre": "12",
        "decembre": "12",
    }
    m = re.match(
        r"(\d{1,2})\s+([A-Za-zéèêëàâîïôöûüç]+)\s+(\d{4})", (datestr or "").strip(), re.I
    )
    if not m:
        return ""
    day, mon, year = m.group(1), m.group(2).lower(), m.group(3)
    mon_num = months.get(mon, "")
    if not mon_num:
        return ""
    return f"{year}-{mon_num}-{int(day):02d}"


def parse_validfrom_date(iso_str: str):
    """
    Return datetime.date from 'YYYY-MM-DD', or None for DB NULL.
    """
    if not iso_str:
        return None
    y, m, d = map(int, iso_str.split("-"))
    return dt.date(y, m, d)


def split_type_text(s: str):
    """
    Split 'Type' into type, places, energy.
    Pattern: '<segment>, <places>, <energy> (example model...)'
    """
    s = s or ""
    s = re.sub(r"\(.*?\)", "", s)  # drop example in parentheses
    parts = [p.strip() for p in s.split(",")]
    while len(parts) < 3:
        parts.append("")
    return parts[0][:30], parts[1][:30], parts[2][:30]  # enforce VARCHAR2(30)


# ============ EXTRACTION (table only) ============


def extract_tarif_table(pdf_bytes: bytes) -> pd.DataFrame:
    """
    Returns DataFrame with columns:
      Type, Cat, Jour, Km   (no € in names)
    Automatically detects headers that contain 'Jour' or 'Km'.
    """
    import pdfplumber
    import tempfile

    df = None

    # Try Camelot first (best for bordered tables)
    if USE_CAMELOT:
        try:
            import camelot

            with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as tmp:
                tmp.write(pdf_bytes)
                tmp_path = tmp.name
            tables = camelot.read_pdf(tmp_path, pages="1-end", flavor="lattice")
            for t in tables:
                head = " ".join(t.df.iloc[0].tolist())
                if "Jour" in head and "Km" in head:
                    raw = t.df.copy()
                    raw.columns = raw.iloc[0]
                    raw = raw.iloc[1:].reset_index(drop=True)
                    break
            else:
                raw = None
            if raw is not None:
                # Normalize headers dynamically
                rename = {}
                for c in raw.columns:
                    cn = (c or "").strip()
                    if "Type" in cn:
                        rename[c] = "Type"
                    elif "Cat" in cn:
                        rename[c] = "Cat"
                    elif re.search(r"Jour", cn, re.I):
                        rename[c] = "Jour"
                    elif re.search(r"\bKm\b", cn, re.I):
                        rename[c] = "Km"
                df = raw.rename(columns=rename)
                df = df[[c for c in ["Type", "Cat", "Jour", "Km"] if c in df.columns]]
        except Exception:
            df = None

    # Fallback with pdfplumber if Camelot fails or returns nothing
    if df is None or df.empty:
        with pdfplumber.open(io.BytesIO(pdf_bytes)) as pdf:
            for page in pdf.pages:
                tables = page.extract_tables()
                for t in tables:
                    header = " ".join([cell or "" for cell in t[0]])
                    if "Jour" in header and "Km" in header:
                        raw = pd.DataFrame(t[1:], columns=t[0])
                        rename = {}
                        for c in raw.columns:
                            cn = (c or "").strip()
                            if "Type" in cn:
                                rename[c] = "Type"
                            elif "Cat" in cn:
                                rename[c] = "Cat"
                            elif re.search(r"Jour", cn, re.I):
                                rename[c] = "Jour"
                            elif re.search(r"\bKm\b", cn, re.I):
                                rename[c] = "Km"
                        df = raw.rename(columns=rename)
                        df = df[
                            [
                                c
                                for c in ["Type", "Cat", "Jour", "Km"]
                                if c in df.columns
                            ]
                        ]
                        break
                if df is not None and not df.empty:
                    break

    if df is None or df.empty:
        raise RuntimeError(
            "No tariff table detected in PDF (no Jour/Km columns found)."
        )

    # Clean numeric columns
    for col in df.columns:
        if col in ("Jour", "Km"):
            df[col] = df[col].apply(normalize_amount_eur)

    return df


# ============ ORACLE LOAD ============


def get_oracle_connection():
    import oracledb  # python-oracledb

    dsn = oracledb.makedsn(ORA_HOST, ORA_PORT, service_name=ORA_SERVICE)
    conn = oracledb.connect(user=ORA_USER, password=ORA_PASSWORD, dsn=dsn)
    return conn


def ensure_table_exists(conn):
    ddl = f"""
    DECLARE
      v_count INTEGER;
    BEGIN
      SELECT COUNT(*) INTO v_count
      FROM user_tables
      WHERE table_name = UPPER('{TARGET_TABLE}');
      IF v_count = 0 THEN
        EXECUTE IMMEDIATE '
          CREATE TABLE {TARGET_TABLE} (
            Cat       VARCHAR2(30) NOT NULL,
            Type      VARCHAR2(30),
            Places    VARCHAR2(30),
            Energy    VARCHAR2(30),
            PrixJour  NUMBER(8,2) CHECK (PrixJour > 0),
            PrixKm    NUMBER(8,2) CHECK (PrixKm > 0),
            ValidFrom DATE
          )';
      END IF;
    END;"""
    with conn.cursor() as cur:
        cur.execute(ddl)
        conn.commit()


def load_into_oracle(df: pd.DataFrame, valid_from_iso: str):
    """
    Append-only loader for historical records.
    Skips insert if the same ValidFrom already exists in Oracle.
    """
    import oracledb

    oracledb.init_oracle_client(lib_dir=r"C:\Oracle\instantclient_23_9")
    print(oracledb.is_thin_mode())

    conn = get_oracle_connection()
    valid_from_date = parse_validfrom_date(valid_from_iso)
    total_inserted = 0

    ensure_table_exists(conn)

    with conn.cursor() as cur:
        # Check if this ValidFrom already exists
        cur.execute(
            f"SELECT COUNT(*) FROM {TARGET_TABLE} WHERE ValidFrom = :v",
            [valid_from_date],
        )
        existing_count = cur.fetchone()[0]

        if existing_count > 0:
            print(
                f"⚠️  Skipping load: {existing_count} rows already exist for ValidFrom={valid_from_iso}."
            )
        else:
            rows = []
            for _, r in df.iterrows():
                t, p, e = split_type_text(r.get("Type"))
                cat = str(r.get("Cat") or "")[:30]
                prix_jour = float(r.get("Jour") or 0)
                prix_km = float(r.get("Km") or 0)
                rows.append((cat, t, p, e, prix_jour, prix_km, valid_from_date))

            cur.executemany(
                f"""INSERT INTO {TARGET_TABLE}
                    (Cat, Type, Places, Energy, PrixJour, PrixKm, ValidFrom)
                    VALUES (:1, :2, :3, :4, :5, :6, :7)""",
                rows,
            )
            total_inserted = cur.rowcount
            print(f"✅ Inserted {total_inserted} rows for ValidFrom={valid_from_iso}.")

    conn.commit()
    conn.close()


# ============ MAIN ============


def main():
    print("Downloading PDF…")
    pdf_bytes = get_pdf_bytes(PDF_LANDING_URL)

    print("Parsing version date…")
    full_text = read_full_text(pdf_bytes)
    version_fr = extract_version_date_fr(full_text)
    valid_from_iso = version_to_iso(version_fr)

    print("Extracting 'Le tarif de location' table…")
    df = extract_tarif_table(pdf_bytes)

    print("Loading into Oracle…")
    load_into_oracle(df, valid_from_iso)

    print(
        f"Done. Loaded {len(df)} rows into {TARGET_TABLE} with ValidFrom={valid_from_iso or 'NULL'}."
    )


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print("ERROR:", e, file=sys.stderr)
        sys.exit(1)
