-- =============================================================================
-- 12_ddl_catalog.sql
-- Schema CATALOG (sgbd_catalog): DDL pentru produse + lookups.
-- Compone:
--   - 4 lookup tables: BRANDS, ITEMS_CATEGORY, ITEMS_TYPE, ITEMS_SEASONS
--   - ITEMS fragmentat vertical (BEA):
--       ITEMS_CORE  (identitate + clasificare, 8 col incl. id)
--       ITEMS_EXTRA (comercial + fizic,        8 col incl. id, FK 1:1 -> CORE)
--
-- View-ul de transparenta V_ITEMS + cele 3 triggere INSTEAD OF aferente sunt
-- mutate in 16_v_items.sql (impreuna cu V_FISE/V_LINII).
-- =============================================================================


-- ============================================================================
-- BRANDS: lookup branduri
-- ============================================================================
CREATE TABLE brands (
    id           NUMBER(19)
  , code         VARCHAR2(3)     NOT NULL
  , brand        VARCHAR2(50)
  , description  VARCHAR2(300)
  , CONSTRAINT pk_brands
        PRIMARY KEY (id)
  , CONSTRAINT uk_brands_code
        UNIQUE (code)
);


-- ============================================================================
-- ITEMS_CATEGORY: lookup categorii produse
-- ============================================================================
CREATE TABLE items_category (
    id        NUMBER(19)
  , code      VARCHAR2(2)     NOT NULL
  , category  VARCHAR2(50)    NOT NULL
  , name      VARCHAR2(50)    NOT NULL
  , CONSTRAINT pk_items_category
        PRIMARY KEY (id)
  , CONSTRAINT uk_cat_code
        UNIQUE (code)
);


-- ============================================================================
-- ITEMS_TYPE: lookup tipuri produse
-- ============================================================================
CREATE TABLE items_type (
    id           NUMBER(19)
  , code         VARCHAR2(4)
  , item_type    VARCHAR2(200)
  , description  VARCHAR2(600)
  , CONSTRAINT pk_items_type
        PRIMARY KEY (id)
  , CONSTRAINT uk_type_code
        UNIQUE (code)
);


-- ============================================================================
-- ITEMS_SEASONS: lookup sezoane
-- NOTE: Coloana SEASON_YEAR are denumire diferita de CSV-ul sursa (YEAR),
--       pentru ca YEAR e cuvant rezervat in Oracle SQL.
-- ============================================================================
CREATE TABLE items_seasons (
    id           NUMBER(19)
  , code         VARCHAR2(120)
  , description  VARCHAR2(40)
  , season_year  VARCHAR2(8)
  , active       NUMBER(10)
  , CONSTRAINT pk_items_seasons
        PRIMARY KEY (id)
  , CONSTRAINT uk_seasons_code
        UNIQUE (code)
  , CONSTRAINT ck_seasons_active
        CHECK (active IN (0, 1))
);


-- ============================================================================
-- ITEMS_CORE: fragmentul vertical 1 = identitate + clasificare
-- (item_code, item_name, FK-uri spre cele 4 lookups, flag active)
-- ============================================================================
CREATE TABLE items_core (
    id            NUMBER(19)
  , item_code     VARCHAR2(50)    NOT NULL
  , item_name     VARCHAR2(350)   NOT NULL
  , brand_id      NUMBER(19)
  , season_id     NUMBER(19)
  , item_type_id  NUMBER(19)
  , category_id   NUMBER(19)
  , active        NUMBER
  , CONSTRAINT pk_items_core
        PRIMARY KEY (id)
  , CONSTRAINT uk_items_code
        UNIQUE (item_code)
  , CONSTRAINT fk_items_brand
        FOREIGN KEY (brand_id)     REFERENCES brands         (id)
  , CONSTRAINT fk_items_season
        FOREIGN KEY (season_id)    REFERENCES items_seasons  (id)
  , CONSTRAINT fk_items_type
        FOREIGN KEY (item_type_id) REFERENCES items_type     (id)
  , CONSTRAINT fk_items_category
        FOREIGN KEY (category_id)  REFERENCES items_category (id)
);


-- ============================================================================
-- ITEMS_EXTRA: fragmentul vertical 2 = atribute comerciale + fizice
-- 1:1 cu ITEMS_CORE prin id (FK + ON DELETE CASCADE pentru curatenie)
-- ============================================================================
CREATE TABLE items_extra (
    id                NUMBER(19)
  , item_description  VARCHAR2(1000)
  , vat               BINARY_DOUBLE
  , last_cost_price   NUMBER(9, 2)
  , main_barcode      VARCHAR2(20)
  , supplier_code     VARCHAR2(60)
  , weight            NUMBER(9, 2)
  , um                VARCHAR2(10)
  , CONSTRAINT pk_items_extra
        PRIMARY KEY (id)
  , CONSTRAINT fk_items_extra_core
        FOREIGN KEY (id) REFERENCES items_core (id) ON DELETE CASCADE
);
