-- =============================================================================
-- 01_create_pdbs.sql
-- Creeaza cele 3 PDB-uri pentru proiectul MODBD: DISTRIBUTIE, CATALOG, VANZARI.
-- Se ruleaza ca SYS in CDB$ROOT. Scriptul este idempotent.
-- =============================================================================


WHENEVER SQLERROR EXIT SQL.SQLCODE


ALTER SESSION SET CONTAINER = CDB$ROOT;


-- ============================================================================
-- Eliminam PDB-ul default XEPDB1 ca sa eliberam slot — idempotent.
-- Oracle XE 21c accepta maxim 3 user PDBs in plus de PDB$SEED.
-- ============================================================================
DECLARE
    not_exist EXCEPTION;
    PRAGMA EXCEPTION_INIT (not_exist, -65011);  -- PDB does not exist
    not_open  EXCEPTION;
    PRAGMA EXCEPTION_INIT (not_open, -65020);   -- PDB already closed
BEGIN
    BEGIN
        EXECUTE IMMEDIATE 'ALTER PLUGGABLE DATABASE XEPDB1 CLOSE IMMEDIATE';
    EXCEPTION
        WHEN not_exist THEN NULL;
        WHEN not_open  THEN NULL;
        WHEN OTHERS    THEN
            IF SQLCODE NOT IN (-65019, -65020, -65011) THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP PLUGGABLE DATABASE XEPDB1 INCLUDING DATAFILES';
    EXCEPTION
        WHEN not_exist THEN NULL;
        WHEN OTHERS    THEN
            IF SQLCODE != -65011 THEN RAISE; END IF;
    END;
END;
/


-- ============================================================================
-- Helper anonim: creeaza un PDB doar daca nu exista deja
-- ============================================================================
DECLARE
    v_exists NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_exists FROM v$pdbs WHERE name = 'DISTRIBUTIE';
    IF v_exists = 0 THEN
        EXECUTE IMMEDIATE q'[
            CREATE PLUGGABLE DATABASE distributie
                ADMIN USER pdb_admin IDENTIFIED BY "ModbdSecret123"
                FILE_NAME_CONVERT = (
                    '/opt/oracle/oradata/XE/pdbseed/'
                  , '/opt/oracle/oradata/XE/distributie/'
                )
        ]';
        EXECUTE IMMEDIATE 'ALTER PLUGGABLE DATABASE distributie OPEN';
    END IF;
END;
/

DECLARE
    v_exists NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_exists FROM v$pdbs WHERE name = 'CATALOG';
    IF v_exists = 0 THEN
        EXECUTE IMMEDIATE q'[
            CREATE PLUGGABLE DATABASE catalog
                ADMIN USER pdb_admin IDENTIFIED BY "ModbdSecret123"
                FILE_NAME_CONVERT = (
                    '/opt/oracle/oradata/XE/pdbseed/'
                  , '/opt/oracle/oradata/XE/catalog/'
                )
        ]';
        EXECUTE IMMEDIATE 'ALTER PLUGGABLE DATABASE catalog OPEN';
    END IF;
END;
/

DECLARE
    v_exists NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_exists FROM v$pdbs WHERE name = 'VANZARI';
    IF v_exists = 0 THEN
        EXECUTE IMMEDIATE q'[
            CREATE PLUGGABLE DATABASE vanzari
                ADMIN USER pdb_admin IDENTIFIED BY "ModbdSecret123"
                FILE_NAME_CONVERT = (
                    '/opt/oracle/oradata/XE/pdbseed/'
                  , '/opt/oracle/oradata/XE/vanzari/'
                )
        ]';
        EXECUTE IMMEDIATE 'ALTER PLUGGABLE DATABASE vanzari OPEN';
    END IF;
END;
/


-- ============================================================================
-- Save state: PDB-urile se deschid automat (READ WRITE) la restart-ul CDB.
-- ============================================================================
ALTER PLUGGABLE DATABASE distributie SAVE STATE;
ALTER PLUGGABLE DATABASE catalog     SAVE STATE;
ALTER PLUGGABLE DATABASE vanzari     SAVE STATE;


-- Verificare finala
SELECT con_id, name, open_mode
FROM   v$pdbs
ORDER BY con_id;
