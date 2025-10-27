BEGIN
    FOR mv IN (
        SELECT mview_name 
        FROM user_mviews 
        WHERE mview_name IN (
            'AGG_R1', 'AGG_R2', 'AGG_R3'
        )
    ) LOOP
        BEGIN
            EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW ' || mv.mview_name;
        EXCEPTION
            WHEN OTHERS THEN NULL;
        END;
    END LOOP;
END;
/

CREATE MATERIALIZED VIEW AGG_R1
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND AS
SELECT
    Mois,
    Annee,
    NomCG,
    VilleCG,
    NomG,
    SUM(DureeReser) AS DureeReser,
    SUM(NbReser) AS NbReser
FROM FAIT_R_RESERVATION FR
JOIN MD_R_CLIENTGENE MC ON FR.CodeCG = MC.CodeCG
JOIN MD_R_TEMP MT ON FR.DateDeb = MT.DateDeb
JOIN MD_R_GAMME MG ON FR.CodeG = MG.CodeG
GROUP BY 
    Mois,
    Annee,
    FR.CodeCG, 
    NomCG, 
    VilleCG, 
    FR.CodeG, 
    NomG;


CREATE MATERIALIZED VIEW AGG_R2
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND AS
SELECT
    Semaine,
    NomG,
    SUM(NbReser)
FROM FAIT_R_RESERVATION FR
JOIN MD_R_TEMP MT ON FR.DateDeb = MT.DateDeb
JOIN MD_R_GAMME MG ON FR.CodeG = MG.CodeG
GROUP BY 
    Semaine,
    FR.CodeG, 
    NomG;


CREATE MATERIALIZED VIEW AGG_R3
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND AS
SELECT
    Annee,
    VilleCG,
    SUM(DureeReser) AS DureeReser,
    SUM(NbReser) AS NbReser
FROM AGG_R1
GROUP BY
    Annee,
    VilleCG;