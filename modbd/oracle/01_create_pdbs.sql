-- =============================================================================
-- 01_create_pdbs.sql
-- Creeaza cele 3 PDB-uri pentru proiectul MODBD: DISTRIBUTIE, CATALOG, VANZARI.
-- Se ruleaza ca SYS in CDB$ROOT.
-- =============================================================================

ALTER SESSION SET CONTAINER = CDB$ROOT;

-- Eliminam PDB-ul default XEPDB1 ca sa eliberam slot (XE accepta max 3 user PDBs).
ALTER PLUGGABLE DATABASE XEPDB1 CLOSE IMMEDIATE;
DROP PLUGGABLE DATABASE XEPDB1 INCLUDING DATAFILES;

-- 1. DISTRIBUTIE -- CRM/Comercial: clienti, zone, agenti, intervale_plata
CREATE PLUGGABLE DATABASE distributie
  ADMIN USER pdb_admin IDENTIFIED BY "ModbdSecret123"
  FILE_NAME_CONVERT = ('/opt/oracle/oradata/XE/pdbseed/',
                       '/opt/oracle/oradata/XE/distributie/');
ALTER PLUGGABLE DATABASE distributie OPEN;

-- 2. CATALOG -- Produse: branduri, sezoane, tipuri, categorii, items
CREATE PLUGGABLE DATABASE catalog
  ADMIN USER pdb_admin IDENTIFIED BY "ModbdSecret123"
  FILE_NAME_CONVERT = ('/opt/oracle/oradata/XE/pdbseed/',
                       '/opt/oracle/oradata/XE/catalog/');
ALTER PLUGGABLE DATABASE catalog OPEN;

-- 3. VANZARI -- Tranzactii: documente (header + linii)
CREATE PLUGGABLE DATABASE vanzari
  ADMIN USER pdb_admin IDENTIFIED BY "ModbdSecret123"
  FILE_NAME_CONVERT = ('/opt/oracle/oradata/XE/pdbseed/',
                       '/opt/oracle/oradata/XE/vanzari/');
ALTER PLUGGABLE DATABASE vanzari OPEN;

-- Salvam starea (READ WRITE) ca sa porneasca automat la restart.
ALTER PLUGGABLE DATABASE distributie SAVE STATE;
ALTER PLUGGABLE DATABASE catalog SAVE STATE;
ALTER PLUGGABLE DATABASE vanzari SAVE STATE;

SELECT con_id, name, open_mode FROM v$pdbs ORDER BY con_id;
