BEGIN
    -- Drop constraints
    FOR c IN (
        SELECT constraint_name, table_name
        FROM user_constraints
        WHERE table_name IN (
            'FAIT_S_LOCATION', 'FAIT_S_AGENCE',
            'MD_S_MODELE', 'MD_S_MARQUE', 'MD_S_TEMP', 'MD_S_AGENCE'
        )
        AND constraint_type IN ('P', 'R', 'U')
    ) LOOP
        BEGIN
            EXECUTE IMMEDIATE 'ALTER TABLE ' || c.table_name || 
                               ' DROP CONSTRAINT ' || c.constraint_name;
            DBMS_OUTPUT.PUT_LINE('Dropped constraint ' || c.constraint_name || ' on ' || c.table_name);
        EXCEPTION
            WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE('⚠️ Could not drop constraint ' || c.constraint_name || ' on ' || c.table_name || ': ' || SQLERRM);
        END;
    END LOOP;

    -- Drop dimensions
    FOR d IN (
        SELECT dimension_name 
        FROM user_dimensions 
        WHERE dimension_name IN (
            'DIM_S_MODELE', 'DIM_S_MARQUE', 'DIM_S_TEMP', 'DIM_S_AGENCE'
        )
    ) LOOP
        BEGIN
            EXECUTE IMMEDIATE 'DROP DIMENSION ' || d.dimension_name;
        EXCEPTION
            WHEN OTHERS THEN NULL;
        END;
    END LOOP;

    -- Drop materialized views
    FOR mv IN (
        SELECT mview_name 
        FROM user_mviews 
        WHERE mview_name IN (
            'FAIT_S_LOCATION', 'FAIT_S_AGENCE',
            'MD_S_MODELE', 'MD_S_MARQUE', 'MD_S_TEMP', 'MD_S_AGENCE'
        )
    ) LOOP
        BEGIN
            EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW ' || mv.mview_name;
        EXCEPTION
            WHEN OTHERS THEN NULL;
        END;
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('✅ All specified materialized views and dimensions dropped successfully.');
END;
/

-- Dimension modèle
CREATE MATERIALIZED VIEW MD_S_MODELE
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND AS
SELECT
    CodeMO,
    NomMO,
    DateCreatMO,
    DateFinMO,
    IntervalleRevision,
    MA.CodeMA AS CodeMAMO,
    NomCO AS NomCOMO,
    MaisonMere AS MaisonMereMO,
    DatecreatCO AS DatecreatCOMO,
    DateFinCO AS DateFinCOMO,
    PaysMA AS PaysCOMO,
    C.CodeTY AS CodeTYMO,
    NomTY AS NomTYMO
FROM BOCHENSOHANDSOME.S2_MODELE MO
JOIN BOCHENTHEHANDSOME.ED_MARQUE MA ON MO.marque = MA.NomMA
LEFT JOIN BOCHENTHEHANDSOME.BRIDGE_MA_CO B ON MA.CodeMA = B.CodeMA
LEFT JOIN BOCHENSOHANDSOME.S1_CONSTRUCTEUR C ON B.CodeCO = C.CodeCO
LEFT JOIN BOCHENSOHANDSOME.S1_TYPECO T ON C.CodeTY = T.CodeTY;

ALTER TABLE MD_S_MODELE
    ADD CONSTRAINT PK_MD_S_MODELE PRIMARY KEY (CodeMO);

CREATE DIMENSION DIM_S_MODELE
    LEVEL CodeMO IS (MD_S_MODELE.CodeMO)
    LEVEL CodeMAMO IS (MD_S_MODELE.CodeMAMO)
    level MaisonMereMO IS (MD_S_MODELE.MaisonMereMO)
    LEVEL CodeTYMO IS (MD_S_MODELE.CodeTYMO)
HIERARCHY H_MasionMereMO (CodeMO CHILD OF CodeMAMO CHILD OF MaisonMereMO)
HIERARCHY H_TypeMO (CodeMO CHILD OF CodeMAMO CHILD OF CodeTYMO)
ATTRIBUTE CodeMO DETERMINES (NomMO, DateCreatMO, DateFinMO, IntervalleRevision)
ATTRIBUTE CodeMAMO DETERMINES (NomCOMO, DatecreatCOMO, DateFinCOMO, PaysCOMO)
ATTRIBUTE CodeTYMO DETERMINES (NomTYMO);


-- Dimension marque
CREATE MATERIALIZED VIEW MD_S_MARQUE
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND AS
SELECT
    MA.CodeMA,
    NomCO,
    MaisonMere,
    DatecreatCO,
    DateFinCO,
    PaysMA,
    C.CodeTY,
    NomTY
FROM BOCHENTHEHANDSOME.ED_MARQUE MA
LEFT JOIN BOCHENTHEHANDSOME.BRIDGE_MA_CO B ON MA.CodeMA = B.CodeMA
LEFT JOIN BOCHENSOHANDSOME.S1_CONSTRUCTEUR C ON B.CodeCO = C.CodeCO
LEFT JOIN BOCHENSOHANDSOME.S1_TYPECO T ON C.CodeTY = T.CodeTY;

ALTER TABLE MD_S_MARQUE
    ADD CONSTRAINT PK_MD_S_MARQUE PRIMARY KEY (CodeMA);

CREATE DIMENSION DIM_S_MARQUE
    LEVEL CodeMA IS (MD_S_MARQUE.CodeMA)
    LEVEL MaisonMere IS (MD_S_MARQUE.MaisonMere)
    LEVEL CodeTY IS (MD_S_MARQUE.CodeTY)
HIERARCHY H_MasionMere (CodeMA CHILD OF MaisonMere)
HIERARCHY H_Type (CodeMA CHILD OF CodeTY)
ATTRIBUTE CodeMA DETERMINES (NomCO, DatecreatCO, DateFinCO, PaysMA)
ATTRIBUTE CodeTY DETERMINES (NomTY);

-- Dimension temporal
CREATE MATERIALIZED VIEW MD_S_TEMP
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND AS
SELECT DISTINCT
    DateDebLoc AS DateDeb,
    TO_CHAR(DateDebLoc, 'YYYY-IW') AS Semaine,
    TO_CHAR(DateDebLoc, 'YYYY-MM') AS Mois,
    TO_CHAR(DateDebLoc, 'YYYY') AS Annee
FROM BOCHENTHEHANDSOME.ED_LOUER;

ALTER TABLE MD_S_TEMP
    ADD CONSTRAINT PK_MD_S_TEMP PRIMARY KEY (DateDeb);

CREATE DIMENSION DIM_S_TEMP
    LEVEL DateDeb IS (MD_S_TEMP.DateDeb)
    LEVEL semaine IS (MD_S_TEMP.semaine)
    LEVEL mois IS (MD_S_TEMP.mois)
    LEVEL annee IS (MD_S_TEMP.annee)
HIERARCHY H_semaine (DateDeb CHILD OF semaine CHILD OF annee)
HIERARCHY H_mois (DateDeb CHILD OF mois CHILD OF annee);


-- Dimension agence
CREATE MATERIALIZED VIEW MD_S_AGENCE
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND AS
SELECT
    CodeAg,
    NomAG,
    TypeAg,
    CPAG,
    RueAG,
    VilleAG,
    QuartierAG
FROM BOCHENSOHANDSOME.S3_AGENCE;

CREATE DIMENSION DIM_S_AGENCE
    LEVEL CodeAg IS (MD_S_AGENCE.CodeAg)
    LEVEL TypeAg IS (MD_S_AGENCE.TypeAg)
    LEVEL VilleAG IS (MD_S_AGENCE.VilleAG)
    LEVEL QuartierAG IS (MD_S_AGENCE.QuartierAG)
HIERARCHY H_TypeAg (CodeAg CHILD OF TypeAg)
HIERARCHY H_VilleAg (CodeAg CHILD OF VilleAG CHILD OF QuartierAG)
ATTRIBUTE CodeAg DETERMINES (NomAG, CPAG, RueAG);


-- Fait location
CREATE MATERIALIZED VIEW FAIT_S_LOCATION
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND AS
SELECT
    MO.CodeMO,
    MA.CodeMA,
    DateDebLoc AS DateDeb,
    SUM(DateFinLoc - DateDebLoc) AS DureeLoc,
    SUM(KmFin - KmDeb) AS NbKm
FROM BOCHENTHEHANDSOME.ED_LOUER L
JOIN BOCHENTHEHANDSOME.ED_VEHICULE VEH ON L.NoImmat = VEH.NoImmat
JOIN BOCHENSOHANDSOME.S2_MODELE MO ON VEH.Modele = MO.NomMO
JOIN BOCHENTHEHANDSOME.ED_MARQUE MA ON MO.marque = MA.NomMA
GROUP BY MO.CodeMO, MA.CodeMA, DateDebLoc;

ALTER TABLE FAIT_S_LOCATION
    ADD CONSTRAINT PK_FAIT_S_LOCATION PRIMARY KEY (CodeMO, CodeMA, DateDeb);


-- Fait Agence
CREATE MATERIALIZED VIEW FAIT_S_AGENCE
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND AS
SELECT
    A.CodeAg,
    DateDebLoc AS DateDeb,
    COUNT(DISTINCT CASE WHEN L.CodeAGDep = A.CodeAg THEN L.NoImmat END) AS NbDepart,
    COUNT(DISTINCT CASE WHEN L.CodeAGRet = A.CodeAg THEN L.NoImmat END) AS NbRetour
FROM BOCHENSOHANDSOME.S3_LOUER L
JOIN BOCHENSOHANDSOME.S3_AGENCE A ON A.CodeAg IN (L.CodeAGDep, L.CodeAGRet)
GROUP BY A.CodeAg, DateDebLoc;

ALTER TABLE FAIT_S_AGENCE
    ADD CONSTRAINT PK_FAIT_S_AGENCE PRIMARY KEY (CodeAg, DateDeb);