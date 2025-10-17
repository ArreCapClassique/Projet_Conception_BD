BEGIN
    -- Drop Fait and Dimension constraints first to avoid dependency errors
    FOR c IN (
        SELECT constraint_name, table_name 
        FROM user_constraints 
        WHERE constraint_name IN (
            'PK_Fait_Reservation', 'PK_Fait_Deplacement',
            'PK_ClientGene', 'PK_Temp', 'PK_Gamme', 'PK_Agence',
            'FK_Fait_Reservation_ClientGene', 'FK_Fait_Reservation_Temp',
            'FK_Fait_Reservation_Gamme', 'FK_Fait_Deplacement_Agence'
        )
    ) LOOP
        BEGIN
            EXECUTE IMMEDIATE 'ALTER TABLE ' || c.table_name || ' DROP CONSTRAINT ' || c.constraint_name;
        EXCEPTION
            WHEN OTHERS THEN NULL;
        END;
    END LOOP;

    -- Drop dimensions
    FOR d IN (
        SELECT dimension_name 
        FROM user_dimensions 
        WHERE dimension_name IN (
            'DIM_CLIENTGENE', 'DIM_TEMP', 'DIM_AGENCE'
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
            'FAIT_RESERVATION', 'FAIT_DEPLACEMENT',
            'MD_CLIENTGENE', 'MD_TEMP', 'MD_GAMME', 'MD_AGENCE'
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


-- Dimension client générique
CREATE MATERIALIZED VIEW MD_CLIENTGENE
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND AS
SELECT
    CONCAT('S_', CodeSoc) AS CodeCG,
    NomSoc AS NomCG,
    RueSoc AS RueCG,
    CPSoc AS CPCG,
    VilleSoc AS VilleCG,
    'NULL' AS RegionCG
FROM ED_SOCIETE
UNION ALL
SELECT
    CONCAT('C_', CodeC) AS CodeCG,
    TRIM(NomC || ' ' || PrenomC) AS NomCG,
    RueC AS RueCG,
    CPC AS CPCG,
    VilleC AS VilleCG,
    RegionC AS RegionCG
FROM ED_CLIENT;

CREATE DIMENSION DIM_CLIENTGENE
    LEVEL CodeCG IS (MD_CLIENTGENE.CodeCG)
    LEVEL VilleCG IS (MD_CLIENTGENE.VilleCG)
    LEVEL RegionCG IS (MD_CLIENTGENE.RegionCG)
HIERARCHY H_Clt (CodeCG CHILD OF VilleCG CHILD OF RegionCG)
ATTRIBUTE CodeCG DETERMINES (NomCG, RueCG, CPCG);


-- Dimension Temporal
CREATE MATERIALIZED VIEW MD_TEMP
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND AS
SELECT DISTINCT
    DateDebSoc AS DateDeb,
    TO_CHAR(DateDebSoc, 'YYYY-IW') AS Semaine,
    TO_CHAR(DateDebSoc, 'YYYY-MM') AS Mois,
    TO_CHAR(DateDebSoc, 'YYYY') AS Annee
FROM ED_ReserverSoc
UNION
SELECT DISTINCT
    DateDebClt AS DateDeb,
    TO_CHAR(DateDebClt, 'YYYY-IW') AS Semaine,
    TO_CHAR(DateDebClt, 'YYYY-MM') AS Mois,
    TO_CHAR(DateDebClt, 'YYYY') AS Annee
FROM ED_ReserverPrive;

CREATE DIMENSION DIM_TEMP
    LEVEL DateDeb IS (MD_TEMP.DateDeb)
    LEVEL semaine IS (MD_TEMP.semaine)
    LEVEL mois IS (MD_TEMP.mois)
    LEVEL annee IS (MD_TEMP.annee)
HIERARCHY H_semaine (DateDeb CHILD OF semaine CHILD OF annee)
HIERARCHY H_mois (DateDeb CHILD OF mois CHILD OF annee);


-- Dimension gamme
CREATE MATERIALIZED VIEW MD_GAMME
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND AS
SELECT
    CodeG,
    NomG
FROM ED_GAMME;


-- Dimension agence
CREATE MATERIALIZED VIEW MD_AGENCE
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

CREATE DIMENSION DIM_AGENCE
    LEVEL CodeAg IS (MD_AGENCE.CodeAg)
    LEVEL TypeAg IS (MD_AGENCE.TypeAg)
    LEVEL QuartierAg IS (MD_AGENCE.QuartierAg)
    LEVEL VilleAg IS (MD_AGENCE.VilleAg)
HIERARCHY H_TypeAg (CodeAg CHILD OF TypeAg)
HIERARCHY H_Agence (CodeAg CHILD OF QuartierAg CHILD OF VilleAg)
ATTRIBUTE CodeAg DETERMINES (NomAg, CPAg, RueAg);


-- Fait réservation
CREATE MATERIALIZED VIEW FAIT_RESERVATION
BUILD IMMEDIATE 
REFRESH COMPLETE ON DEMAND AS
SELECT
    CONCAT('S_', CodeSoc) AS CodeCG,
    CodeG,
    DateDebSoc AS DateDeb,
    COUNT(*) AS NbReser,
    SUM(DateFinSoc - DateDebSoc) AS DureeReser
FROM ED_ReserverSoc
GROUP BY CodeSoc, CodeG, DateDebSoc
UNION ALL
SELECT
    CONCAT('C_', CodeC) AS CodeCG,
    CodeG,
    DateDebClt AS DateDeb,
    COUNT(*) AS NbReser,
    SUM(DateFinClt - DateDebClt) AS DureeReser
FROM ED_ReserverPrive
GROUP BY CodeC, CodeG, DateDebClt;

ALTER TABLE FAIT_RESERVATION
ADD CONSTRAINT PK_Fait_Reservation PRIMARY KEY (CodeCG, CodeG, DateDeb);

ALTER TABLE FAIT_RESERVATION
ADD CONSTRAINT FK_Fait_Reservation_ClientGene FOREIGN KEY (CodeCG) REFERENCES MD_CLIENTGENE(CodeCG)
ADD CONSTRAINT FK_Fait_Reservation_Temp FOREIGN KEY (DateDeb) REFERENCES MD_TEMP(DateDeb)
ADD CONSTRAINT FK_Fait_Reservation_Gamme FOREIGN KEY (CodeG) REFERENCES MD_GAMME(CodeG);


-- Fait déplacement
CREATE MATERIALIZED VIEW FAIT_DEPLACEMENT
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND AS
WITH DEPARTURE AS (
    SELECT
        CodeAGDep AS CodeAg, 
        DateDebSoc AS DateAg, 
        COUNT(*) AS NbDep
    FROM BOCHENSOHANDSOME.S3_ReserverSoc
    GROUP BY CodeAGDep, DateDebSoc
    UNION ALL
    SELECT
        CodeAGDep AS CodeAg, 
        DateDebClt AS DateAg, 
        COUNT(*) AS NbDep
    FROM BOCHENSOHANDSOME.S3_ReserverPrive
    GROUP BY CodeAGDep, DateDebClt
),
ARRIVAL AS (
    SELECT
        CodeAGRet AS CodeAg, 
        DateFinSoc AS DateAg, 
        COUNT(*) AS NbRet
    FROM BOCHENSOHANDSOME.S3_ReserverSoc
    GROUP BY CodeAGRet, DateFinSoc
    UNION ALL
    SELECT
        CodeAGRet AS CodeAg, 
        DateFinClt AS DateAg, 
        COUNT(*) AS NbRet
    FROM BOCHENSOHANDSOME.S3_ReserverPrive
    GROUP BY CodeAGRet, DateFinClt
)
SELECT
    NVL(d.CodeAg, a.CodeAg) AS CodeAg,
    NVL(d.DateAg, a.DateAg) AS DateAg,
    NVL(d.NbDep, 0) AS NbDep,
    NVL(a.NbRet, 0) AS NbRet,
    NVL(d.NbDep, 0) - NVL(a.NbRet, 0) AS Diff_Dep_Ret
FROM DEPARTURE d
FULL OUTER JOIN ARRIVAL a
    ON d.CodeAg = a.CodeAg AND d.DateAg = a.DateAg
ORDER BY CodeAg, DateAg;

ALTER TABLE FAIT_DEPLACEMENT
ADD CONSTRAINT PK_Fait_Deplacement PRIMARY KEY (CodeAg, DateAg);