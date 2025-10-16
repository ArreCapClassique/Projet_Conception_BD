SET DEFINE OFF
SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON
WHENEVER SQLERROR EXIT SQL.SQLCODE
WHENEVER OSERROR  EXIT 9

-- Drop in dependency order
BEGIN EXECUTE IMMEDIATE 'DROP TABLE S3_LOUER PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE S3_RESERVERPRIVE PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE S3_RESERVERSOC PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE S3_AGENCE PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/

-- Master: agencies
CREATE TABLE S3_AGENCE (
  CodeAg     NUMBER       PRIMARY KEY,
  NomAG      VARCHAR2(60) NOT NULL,
  TypeAg     VARCHAR2(10) NOT NULL CHECK (LOWER(TypeAg) IN ('ville','gare','aéroport')),
  CPAG       CHAR(5)      NOT NULL,
  RueAG      VARCHAR2(80) NOT NULL,
  VilleAG    VARCHAR2(50) NOT NULL,
  QuartierAG VARCHAR2(50) NOT NULL
);

-- Private reservations + agencies
CREATE TABLE S3_RESERVERPRIVE (
  CodeC      NUMBER       NOT NULL,
  DateDebClt DATE         NOT NULL,
  CodeG      NUMBER       NOT NULL,
  CodeAGDep  NUMBER       NOT NULL REFERENCES S3_AGENCE(CodeAg),
  DateFinClt DATE         NOT NULL,
  DateResa   DATE         NOT NULL,
  CodeAgRet  NUMBER       NOT NULL REFERENCES S3_AGENCE(CodeAg),
  CONSTRAINT pk_s3_resprv PRIMARY KEY (CodeC, DateDebClt, CodeG),
  CONSTRAINT chk_s3_resprv_dates
    CHECK (DateFinClt >= DateDebClt AND DateDebClt >= DateResa)
);

-- Corporate reservations + agencies
CREATE TABLE S3_RESERVERSOC (
  CodeSoc     CHAR(14)    NOT NULL,
  DateDebSoc  DATE        NOT NULL,
  CodeG       NUMBER      NOT NULL,
  CodeAGDep   NUMBER      NOT NULL REFERENCES S3_AGENCE(CodeAg),
  DateFinSoc  DATE        NOT NULL,
  DateResaSoc DATE        NOT NULL,
  CodeAgRet   NUMBER      NOT NULL REFERENCES S3_AGENCE(CodeAg),
  CONSTRAINT pk_s3_ressoc PRIMARY KEY (CodeSoc, DateDebSoc, CodeG),
  CONSTRAINT chk_s3_ressoc_dates
    CHECK (DateFinSoc >= DateDebSoc AND DateDebSoc >= DateResaSoc)
);

-- Rentals + agencies
CREATE TABLE S3_LOUER (
  CodeC      NUMBER       NOT NULL,
  NoImmat    VARCHAR2(9)  NOT NULL,
  DateDebLoc DATE         NOT NULL,
  CodeAGDep  NUMBER       NOT NULL REFERENCES S3_AGENCE(CodeAg),
  DateFinLoc DATE         NOT NULL,
  KmDeb      NUMBER       NOT NULL CHECK (KmDeb > 0),
  KmFin      NUMBER       NOT NULL,
  CodeAgRet  NUMBER       NOT NULL REFERENCES S3_AGENCE(CodeAg),
  CONSTRAINT pk_s3_louer PRIMARY KEY (CodeC, NoImmat, DateDebLoc),
  CONSTRAINT chk_s3_louer_km    CHECK (KmFin > KmDeb),
  CONSTRAINT chk_s3_louer_dates CHECK (DateFinLoc >= DateDebLoc)
);

-- Helpful indexes (like ED)
CREATE INDEX idx_s3_resprv_dates ON S3_RESERVERPRIVE(DateDebClt, DateFinClt);
CREATE INDEX idx_s3_ressoc_dates ON S3_RESERVERSOC(DateDebSoc,  DateFinSoc);
CREATE INDEX idx_s3_louer_dates  ON S3_LOUER(DateDebLoc,        DateFinLoc);

PROMPT S3 DDL completed.
EXIT
