-- =============================================================================
-- 03_csv_directory.sql
-- Creeaza directory object CSV_DIR pointand la /csv (mount-ul Docker) in fiecare
-- PDB si acorda READ pe el utilizatorilor aplicativi.
-- Necesar pentru external tables care citesc CSV-urile la load-ul de date.
-- Se ruleaza ca SYS, alternand intre PDB-uri prin ALTER SESSION.
-- =============================================================================


-- ============================================================================
-- DISTRIBUTIE
-- ============================================================================
ALTER SESSION SET CONTAINER = DISTRIBUTIE;

CREATE OR REPLACE DIRECTORY csv_dir AS '/csv';

GRANT READ ON DIRECTORY csv_dir TO sgbd_distributie;


-- ============================================================================
-- CATALOG
-- ============================================================================
ALTER SESSION SET CONTAINER = CATALOG;

CREATE OR REPLACE DIRECTORY csv_dir AS '/csv';

GRANT READ ON DIRECTORY csv_dir TO sgbd_catalog;


-- ============================================================================
-- VANZARI
-- ============================================================================
ALTER SESSION SET CONTAINER = VANZARI;

CREATE OR REPLACE DIRECTORY csv_dir AS '/csv';

GRANT READ ON DIRECTORY csv_dir TO sgbd_vanzari;
