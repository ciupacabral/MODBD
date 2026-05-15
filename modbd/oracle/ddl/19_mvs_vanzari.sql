-- =============================================================================
-- 19_mvs_vanzari.sql
-- MV-uri replicate in VANZARI care oglindesc tabelele master din DISTRIBUTIE
-- si CATALOG. Strategie: REFRESH FAST ON DEMAND (cross-PDB nu suporta ON COMMIT).
-- UK pe coloana de business permite FK-uri locale catre MV-uri (Task urmator).
-- =============================================================================

-- ===== Replici din DISTRIBUTIE =====
CREATE MATERIALIZED VIEW mv_clienti
  BUILD IMMEDIATE
  REFRESH FAST ON DEMAND
  WITH PRIMARY KEY
  AS SELECT * FROM clienti@lnk_distributie;
ALTER TABLE mv_clienti ADD CONSTRAINT uk_mv_clienti_cod UNIQUE (cod_client);

CREATE MATERIALIZED VIEW mv_zone
  BUILD IMMEDIATE
  REFRESH FAST ON DEMAND
  WITH PRIMARY KEY
  AS SELECT * FROM zone@lnk_distributie;

-- ===== Replici din CATALOG =====
CREATE MATERIALIZED VIEW mv_items_core
  BUILD IMMEDIATE
  REFRESH FAST ON DEMAND
  WITH PRIMARY KEY
  AS SELECT * FROM items_core@lnk_catalog;
ALTER TABLE mv_items_core ADD CONSTRAINT uk_mv_items_code UNIQUE (item_code);

CREATE MATERIALIZED VIEW mv_brands
  BUILD IMMEDIATE
  REFRESH FAST ON DEMAND
  WITH PRIMARY KEY
  AS SELECT * FROM brands@lnk_catalog;

CREATE MATERIALIZED VIEW mv_items_category
  BUILD IMMEDIATE
  REFRESH FAST ON DEMAND
  WITH PRIMARY KEY
  AS SELECT * FROM items_category@lnk_catalog;

CREATE MATERIALIZED VIEW mv_items_type
  BUILD IMMEDIATE
  REFRESH FAST ON DEMAND
  WITH PRIMARY KEY
  AS SELECT * FROM items_type@lnk_catalog;

CREATE MATERIALIZED VIEW mv_items_seasons
  BUILD IMMEDIATE
  REFRESH FAST ON DEMAND
  WITH PRIMARY KEY
  AS SELECT * FROM items_seasons@lnk_catalog;
