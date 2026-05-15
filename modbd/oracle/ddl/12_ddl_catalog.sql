-- =============================================================================
-- 12_ddl_catalog.sql
-- Schema CATALOG (sgbd_catalog): produse + lookups.
-- Compone:
--   - 4 lookup tables: BRANDS, ITEMS_CATEGORY, ITEMS_TYPE, ITEMS_SEASONS
--   - ITEMS fragmentat vertical:
--       ITEMS_CORE  (identitate + clasificare, 8 col incl. id)
--       ITEMS_EXTRA (comercial + fizic,        8 col incl. id, FK 1:1 -> CORE)
--   - V_ITEMS = view de transparenta verticala (JOIN pe id)
--   - 3 triggere INSTEAD OF pe V_ITEMS pentru DML transparent
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


-- ============================================================================
-- V_ITEMS: view de transparenta verticala (JOIN intre CORE si EXTRA dupa id)
-- Expune toate cele 15 coloane originale ale ITEMS.
-- ============================================================================
CREATE OR REPLACE VIEW v_items (
    id
  , item_code
  , item_name
  , item_description
  , brand_id
  , season_id
  , item_type_id
  , category_id
  , vat
  , last_cost_price
  , main_barcode
  , supplier_code
  , weight
  , um
  , active
) AS
SELECT
    c.id
  , c.item_code
  , c.item_name
  , e.item_description
  , c.brand_id
  , c.season_id
  , c.item_type_id
  , c.category_id
  , e.vat
  , e.last_cost_price
  , e.main_barcode
  , e.supplier_code
  , e.weight
  , e.um
  , c.active
FROM   items_core  c
       JOIN items_extra e
            ON e.id = c.id;


-- ============================================================================
-- Trigger INSTEAD OF INSERT pe V_ITEMS
-- Sparge insertul in 2: o linie in CORE + o linie in EXTRA (acelasi id).
-- ============================================================================
CREATE OR REPLACE TRIGGER trg_v_items_ins
INSTEAD OF INSERT ON v_items
FOR EACH ROW
BEGIN

    INSERT INTO items_core (
        id
      , item_code
      , item_name
      , brand_id
      , season_id
      , item_type_id
      , category_id
      , active
    ) VALUES (
        :NEW.id
      , :NEW.item_code
      , :NEW.item_name
      , :NEW.brand_id
      , :NEW.season_id
      , :NEW.item_type_id
      , :NEW.category_id
      , :NEW.active
    );

    INSERT INTO items_extra (
        id
      , item_description
      , vat
      , last_cost_price
      , main_barcode
      , supplier_code
      , weight
      , um
    ) VALUES (
        :NEW.id
      , :NEW.item_description
      , :NEW.vat
      , :NEW.last_cost_price
      , :NEW.main_barcode
      , :NEW.supplier_code
      , :NEW.weight
      , :NEW.um
    );

END;
/


-- ============================================================================
-- Trigger INSTEAD OF UPDATE pe V_ITEMS
-- Update simultan in ambele fragmente. PK-ul (id) ramane neschimbat.
-- ============================================================================
CREATE OR REPLACE TRIGGER trg_v_items_upd
INSTEAD OF UPDATE ON v_items
FOR EACH ROW
BEGIN

    UPDATE items_core
    SET
        item_code    = :NEW.item_code
      , item_name    = :NEW.item_name
      , brand_id     = :NEW.brand_id
      , season_id    = :NEW.season_id
      , item_type_id = :NEW.item_type_id
      , category_id  = :NEW.category_id
      , active       = :NEW.active
    WHERE id = :OLD.id;

    UPDATE items_extra
    SET
        item_description = :NEW.item_description
      , vat              = :NEW.vat
      , last_cost_price  = :NEW.last_cost_price
      , main_barcode     = :NEW.main_barcode
      , supplier_code    = :NEW.supplier_code
      , weight           = :NEW.weight
      , um               = :NEW.um
    WHERE id = :OLD.id;

END;
/


-- ============================================================================
-- Trigger INSTEAD OF DELETE pe V_ITEMS
-- DELETE pe items_core => ON DELETE CASCADE sterge automat items_extra.
-- ============================================================================
CREATE OR REPLACE TRIGGER trg_v_items_del
INSTEAD OF DELETE ON v_items
FOR EACH ROW
BEGIN

    DELETE FROM items_core
    WHERE id = :OLD.id;

END;
/
