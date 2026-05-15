-- =============================================================================
-- 01_create_pdbs.sql
-- Creeaza cele 3 PDB-uri pentru proiectul MODBD: DISTRIBUTIE, CATALOG, VANZARI.
-- Se ruleaza ca SYS in CDB$ROOT.
-- =============================================================================


ALTER SESSION SET CONTAINER = CDB$ROOT;


-- ============================================================================
-- Eliminam PDB-ul default XEPDB1 ca sa eliberam slot.
-- Oracle XE 21c accepta maxim 3 user PDBs in plus de PDB$SEED.
-- ============================================================================
ALTER PLUGGABLE DATABASE XEPDB1 CLOSE IMMEDIATE;
DROP  PLUGGABLE DATABASE XEPDB1 INCLUDING DATAFILES;


-- ============================================================================
-- PDB #1: DISTRIBUTIE
-- Domeniu CRM/comercial: clienti, zone, agenti, intervale de plata, M:N-uri.
-- ============================================================================
CREATE PLUGGABLE DATABASE distributie
    ADMIN USER pdb_admin IDENTIFIED BY "ModbdSecret123"
    FILE_NAME_CONVERT = (
        '/opt/oracle/oradata/XE/pdbseed/'
      , '/opt/oracle/oradata/XE/distributie/'
    );

ALTER PLUGGABLE DATABASE distributie OPEN;


-- ============================================================================
-- PDB #2: CATALOG
-- Domeniu produse: branduri, sezoane, tipuri, categorii, items (CORE + EXTRA).
-- ============================================================================
CREATE PLUGGABLE DATABASE catalog
    ADMIN USER pdb_admin IDENTIFIED BY "ModbdSecret123"
    FILE_NAME_CONVERT = (
        '/opt/oracle/oradata/XE/pdbseed/'
      , '/opt/oracle/oradata/XE/catalog/'
    );

ALTER PLUGGABLE DATABASE catalog OPEN;


-- ============================================================================
-- PDB #3: VANZARI
-- Domeniu tranzactii: fise documente (header) + linii (M:N).
-- ============================================================================
CREATE PLUGGABLE DATABASE vanzari
    ADMIN USER pdb_admin IDENTIFIED BY "ModbdSecret123"
    FILE_NAME_CONVERT = (
        '/opt/oracle/oradata/XE/pdbseed/'
      , '/opt/oracle/oradata/XE/vanzari/'
    );

ALTER PLUGGABLE DATABASE vanzari OPEN;


-- ============================================================================
-- SAVE STATE: PDB-urile se deschid automat (READ WRITE) la restart-ul CDB.
-- ============================================================================
ALTER PLUGGABLE DATABASE distributie SAVE STATE;
ALTER PLUGGABLE DATABASE catalog     SAVE STATE;
ALTER PLUGGABLE DATABASE vanzari     SAVE STATE;


-- Verificare finala
SELECT con_id, name, open_mode
FROM   v$pdbs
ORDER BY con_id;
