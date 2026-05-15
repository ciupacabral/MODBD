-- =============================================================================
-- 19_mvs_vanzari.sql
-- MV-uri replicate in VANZARI care oglindesc tabelele master din DISTRIBUTIE
-- si CATALOG. Strategia: REFRESH FAST ON DEMAND.
--
-- De ce ON DEMAND si nu ON COMMIT:
--   ON COMMIT functioneaza doar daca master-ul e in aceeasi baza ca MV-ul.
--   PDB-urile cross-link sunt tratate ca distribuite => ON COMMIT inaplicabil.
--   Sincronizarea se face printr-un job DBMS_SCHEDULER (vezi 21_refresh_job.sql).
--
-- UK pe coloana de business (cod_client, item_code) e necesar pentru a permite
-- FK-uri locale catre MV-uri (Task 12: 20_cross_pdb_fks.sql).
-- =============================================================================


-- ============================================================================
-- MV_CLIENTI: replica DISTRIBUTIE.clienti
-- ============================================================================
CREATE MATERIALIZED VIEW mv_clienti
    BUILD IMMEDIATE
    REFRESH FAST ON DEMAND
    WITH PRIMARY KEY
AS
SELECT *
FROM   clienti@lnk_distributie;

ALTER TABLE mv_clienti
ADD CONSTRAINT uk_mv_clienti_cod UNIQUE (cod_client);


-- ============================================================================
-- MV_ZONE: replica DISTRIBUTIE.zone
-- ============================================================================
CREATE MATERIALIZED VIEW mv_zone
    BUILD IMMEDIATE
    REFRESH FAST ON DEMAND
    WITH PRIMARY KEY
AS
SELECT *
FROM   zone@lnk_distributie;


-- ============================================================================
-- MV_ITEMS_CORE: replica CATALOG.items_core (fragment vertical CORE)
-- ============================================================================
CREATE MATERIALIZED VIEW mv_items_core
    BUILD IMMEDIATE
    REFRESH FAST ON DEMAND
    WITH PRIMARY KEY
AS
SELECT *
FROM   items_core@lnk_catalog;

ALTER TABLE mv_items_core
ADD CONSTRAINT uk_mv_items_code UNIQUE (item_code);


-- ============================================================================
-- MV_BRANDS: replica CATALOG.brands
-- ============================================================================
CREATE MATERIALIZED VIEW mv_brands
    BUILD IMMEDIATE
    REFRESH FAST ON DEMAND
    WITH PRIMARY KEY
AS
SELECT *
FROM   brands@lnk_catalog;


-- ============================================================================
-- MV_ITEMS_CATEGORY: replica CATALOG.items_category
-- ============================================================================
CREATE MATERIALIZED VIEW mv_items_category
    BUILD IMMEDIATE
    REFRESH FAST ON DEMAND
    WITH PRIMARY KEY
AS
SELECT *
FROM   items_category@lnk_catalog;


-- ============================================================================
-- MV_ITEMS_TYPE: replica CATALOG.items_type
-- ============================================================================
CREATE MATERIALIZED VIEW mv_items_type
    BUILD IMMEDIATE
    REFRESH FAST ON DEMAND
    WITH PRIMARY KEY
AS
SELECT *
FROM   items_type@lnk_catalog;


-- ============================================================================
-- MV_ITEMS_SEASONS: replica CATALOG.items_seasons
-- ============================================================================
CREATE MATERIALIZED VIEW mv_items_seasons
    BUILD IMMEDIATE
    REFRESH FAST ON DEMAND
    WITH PRIMARY KEY
AS
SELECT *
FROM   items_seasons@lnk_catalog;
