-- =============================================================================
-- 03_csv_directory.sql
-- Creeaza directory object CSV_DIR pointand la /csv (mount-ul Docker) in fiecare
-- PDB si acorda READ pe el utilizatorilor aplicativi.
-- =============================================================================

ALTER SESSION SET CONTAINER = DISTRIBUTIE;
CREATE OR REPLACE DIRECTORY csv_dir AS '/csv';
GRANT READ ON DIRECTORY csv_dir TO sgbd_distributie;

ALTER SESSION SET CONTAINER = CATALOG;
CREATE OR REPLACE DIRECTORY csv_dir AS '/csv';
GRANT READ ON DIRECTORY csv_dir TO sgbd_catalog;

ALTER SESSION SET CONTAINER = VANZARI;
CREATE OR REPLACE DIRECTORY csv_dir AS '/csv';
GRANT READ ON DIRECTORY csv_dir TO sgbd_vanzari;
