BEGIN
    FOR mv IN (
        SELECT mview_name 
        FROM user_mviews 
        WHERE mview_name IN (
            'AGG_S1', 'AGG_S2'
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

CREATE MATERIALIZED VIEW AGG_S1
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND AS
SELECT
    Mois,
    FL.CodeMO,
    NomMO,
    SUM(NbKm) AS NbKm
FROM FAIT_S_LOCATION FL
JOIN MD_S_MODELE MM ON FL.CodeMO = MM.CodeMO
JOIN MD_S_TEMP MT ON FL.DateDeb = MT.DateDeb
GROUP BY
    Mois,
    FL.CodeMO,
    NomMO;


CREATE MATERIALIZED VIEW AGG_S2
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND AS
SELECT
    Mois,
    CodeAG,
    SUM(NbDepart) AS NbDepart,
    SUM(NbRetour) AS NbRetour
FROM FAIT_S_AGENCE FA
JOIN MD_S_TEMP MT ON FA.DateDeb = MT.DateDeb
GROUP BY
    Mois,
    CodeAG;
