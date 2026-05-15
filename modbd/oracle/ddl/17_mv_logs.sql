-- =============================================================================
-- 17_mv_logs.sql
-- MV logs pe tabelele care vor fi replicate cross-PDB (DISTRIBUTIE + CATALOG).
-- WITH PRIMARY KEY, ROWID, SEQUENCE INCLUDING NEW VALUES = configuratia
-- standard care permite REFRESH FAST sa functioneze in toate cazurile
-- (inclusiv pe MV-uri cu subqueries / joins / agregate).
-- Se ruleaza ca SYS, alternand intre PDB-uri prin ALTER SESSION.
-- =============================================================================


-- ============================================================================
-- DISTRIBUTIE: MV logs pe tabelele master care vor fi replicate in VANZARI
-- ============================================================================
ALTER SESSION SET CONTAINER       = DISTRIBUTIE;
ALTER SESSION SET CURRENT_SCHEMA  = sgbd_distributie;


CREATE MATERIALIZED VIEW LOG ON clienti
    WITH PRIMARY KEY, ROWID, SEQUENCE
    INCLUDING NEW VALUES;


CREATE MATERIALIZED VIEW LOG ON zone
    WITH PRIMARY KEY, ROWID, SEQUENCE
    INCLUDING NEW VALUES;


-- ============================================================================
-- CATALOG: MV logs pe tabelele master + items_core (fragment vertical)
-- ============================================================================
ALTER SESSION SET CONTAINER       = CATALOG;
ALTER SESSION SET CURRENT_SCHEMA  = sgbd_catalog;


CREATE MATERIALIZED VIEW LOG ON items_core
    WITH PRIMARY KEY, ROWID, SEQUENCE
    INCLUDING NEW VALUES;


CREATE MATERIALIZED VIEW LOG ON brands
    WITH PRIMARY KEY, ROWID, SEQUENCE
    INCLUDING NEW VALUES;


CREATE MATERIALIZED VIEW LOG ON items_category
    WITH PRIMARY KEY, ROWID, SEQUENCE
    INCLUDING NEW VALUES;


CREATE MATERIALIZED VIEW LOG ON items_type
    WITH PRIMARY KEY, ROWID, SEQUENCE
    INCLUDING NEW VALUES;


CREATE MATERIALIZED VIEW LOG ON items_seasons
    WITH PRIMARY KEY, ROWID, SEQUENCE
    INCLUDING NEW VALUES;
