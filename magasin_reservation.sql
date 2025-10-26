BEGIN
    -- Drop constraints
    FOR c IN (
        SELECT constraint_name, table_name
        FROM user_constraints
        WHERE table_name IN (
            'FAIT_R_RESERVATION',
            'MD_R_CLIENTGENE', 'MD_R_TEMP', 'MD_R_GAMME'
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
            'DIM_R_CLIENTGENE', 'DIM_R_TEMP', 'DIM_R_AGENCE'
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
            'FAIT_R_RESERVATION',
            'MD_R_CLIENTGENE', 'MD_R_TEMP', 'MD_R_GAMME'
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
CREATE MATERIALIZED VIEW MD_R_CLIENTGENE
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND AS
SELECT
    'S:' || CodeSoc AS CodeCG,
    NomSoc AS NomCG,
    RueSoc AS RueCG,
    CPSoc AS CPCG,
    VilleSoc AS VilleCG,
    CAST(NULL AS VARCHAR2(50)) AS RegionCG
FROM ED_SOCIETE
UNION ALL
SELECT
    'C:' || TO_CHAR(CodeC) AS CodeCG,
    TRIM(NomC || ' ' || PrenomC) AS NomCG,
    RueC AS RueCG,
    CPC AS CPCG,
    VilleC AS VilleCG,
    RegionC AS RegionCG
FROM ED_CLIENT;

ALTER TABLE MD_R_CLIENTGENE
    ADD CONSTRAINT PK_MD_R_CLIENTGENE PRIMARY KEY (CodeCG);

CREATE DIMENSION DIM_R_CLIENTGENE
    LEVEL CodeCG IS (MD_R_CLIENTGENE.CodeCG)
    LEVEL VilleCG IS (MD_R_CLIENTGENE.VilleCG)
    LEVEL RegionCG IS (MD_R_CLIENTGENE.RegionCG)
HIERARCHY H_Clt (CodeCG CHILD OF VilleCG CHILD OF RegionCG)
ATTRIBUTE CodeCG DETERMINES (NomCG, RueCG, CPCG);


-- Dimension Temporal
CREATE MATERIALIZED VIEW MD_R_TEMP
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

ALTER TABLE MD_R_TEMP
    ADD CONSTRAINT PK_MD_R_TEMP PRIMARY KEY (DateDeb);

CREATE DIMENSION DIM_R_TEMP
    LEVEL DateDeb IS (MD_R_TEMP.DateDeb)
    LEVEL semaine IS (MD_R_TEMP.semaine)
    LEVEL mois IS (MD_R_TEMP.mois)
    LEVEL annee IS (MD_R_TEMP.annee)
HIERARCHY H_semaine (DateDeb CHILD OF semaine CHILD OF annee)
HIERARCHY H_mois (DateDeb CHILD OF mois CHILD OF annee);
    

-- Dimension gamme
CREATE MATERIALIZED VIEW MD_R_GAMME
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND AS
SELECT
    CodeG,
    NomG
FROM ED_GAMME;


-- Fait réservation
CREATE MATERIALIZED VIEW FAIT_R_RESERVATION
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND AS
SELECT
    'S:' || CodeSoc AS CodeCG,
    CodeG,
    DateDebSoc AS DateDeb,
    COUNT(*) AS NbReser,
    SUM(DateFinSoc - DateDebSoc) AS DureeReser
FROM ED_ReserverSoc
GROUP BY 'S:' || CodeSoc, CodeG, DateDebSoc
UNION ALL
SELECT
    'C:' || TO_CHAR(CodeC) AS CodeCG,
    CodeG,
    DateDebClt AS DateDeb,
    COUNT(*) AS NbReser,
    SUM(DateFinClt - DateDebClt) AS DureeReser
FROM ED_ReserverPrive
GROUP BY 'C:' || TO_CHAR(CodeC), CodeG, DateDebClt;

ALTER TABLE FAIT_R_RESERVATION
ADD CONSTRAINT PK_Fait_Reservation PRIMARY KEY (CodeCG, CodeG, DateDeb);

ALTER TABLE FAIT_R_RESERVATION
ADD CONSTRAINT FK_Fait_Reservation_ClientGene FOREIGN KEY (CodeCG) REFERENCES MD_R_CLIENTGENE(CodeCG);
ALTER TABLE FAIT_R_RESERVATION
ADD CONSTRAINT FK_Fait_Reservation_Temp FOREIGN KEY (DateDeb) REFERENCES MD_R_TEMP(DateDeb);
ALTER TABLE FAIT_R_RESERVATION
ADD CONSTRAINT FK_Fait_Reservation_Gamme FOREIGN KEY (CodeG) REFERENCES MD_R_GAMME(CodeG);
