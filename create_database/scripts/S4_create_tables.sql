-- Drop in dependency order
BEGIN EXECUTE IMMEDIATE 'DROP TABLE S4_AVIS PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/

-- Master: agencies
CREATE TABLE S4_AVIS (
  Cat       VARCHAR2(30) NOT NULL,
  Type      VARCHAR2(30),
  Places    VARCHAR2(30),
  Energy    VARCHAR2(30),
  PrixJour  NUMBER(8,2) CHECK (PrixJour > 0),
  PrixKm    NUMBER(8,2) CHECK (PrixKm > 0),
  ValidFrom DATE
);