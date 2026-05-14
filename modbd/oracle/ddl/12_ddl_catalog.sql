-- =============================================================================
-- 12_ddl_catalog.sql
-- Schema CATALOG (sgbd_catalog): produse + lookups.
-- 4 lookup tables (BRANDS, ITEMS_CATEGORY, ITEMS_TYPE, ITEMS_SEASONS)
-- + ITEMS fragmentat vertical in ITEMS_CORE (8 col) + ITEMS_EXTRA (8 col)
-- + V_ITEMS (view de transparenta verticala, JOIN pe id)
-- + 3 triggere INSTEAD OF pe V_ITEMS pentru DML transparent.
-- =============================================================================

-- ------ Lookups ------
CREATE TABLE brands (
  id           NUMBER(19) PRIMARY KEY,
  code         VARCHAR2(3)   NOT NULL,
  brand        VARCHAR2(50),
  description  VARCHAR2(300),
  CONSTRAINT uk_brands_code UNIQUE (code)
);

CREATE TABLE items_category (
  id        NUMBER(19) PRIMARY KEY,
  code      VARCHAR2(2)  NOT NULL,
  category  VARCHAR2(50) NOT NULL,
  name      VARCHAR2(50) NOT NULL,
  CONSTRAINT uk_cat_code UNIQUE (code)
);

CREATE TABLE items_type (
  id           NUMBER(19) PRIMARY KEY,
  code         VARCHAR2(4),
  item_type    VARCHAR2(200),
  description  VARCHAR2(600),
  CONSTRAINT uk_type_code UNIQUE (code)
);

CREATE TABLE items_seasons (
  id           NUMBER(19) PRIMARY KEY,
  code         VARCHAR2(120),
  description  VARCHAR2(40),
  season_year  VARCHAR2(8),    -- 'year' e cuvant rezervat in Oracle
  active       NUMBER(10),
  CONSTRAINT uk_seasons_code UNIQUE (code),
  CONSTRAINT ck_seasons_active CHECK (active IN (0,1))
);

-- ------ ITEMS fragmentat vertical ------
CREATE TABLE items_core (
  id            NUMBER(19) PRIMARY KEY,
  item_code     VARCHAR2(50)  NOT NULL,
  item_name     VARCHAR2(350) NOT NULL,
  brand_id      NUMBER(19),
  season_id     NUMBER(19),
  item_type_id  NUMBER(19),
  category_id   NUMBER(19),
  active        NUMBER,
  CONSTRAINT uk_items_code UNIQUE (item_code),
  CONSTRAINT fk_items_brand    FOREIGN KEY (brand_id)     REFERENCES brands(id),
  CONSTRAINT fk_items_season   FOREIGN KEY (season_id)    REFERENCES items_seasons(id),
  CONSTRAINT fk_items_type     FOREIGN KEY (item_type_id) REFERENCES items_type(id),
  CONSTRAINT fk_items_category FOREIGN KEY (category_id)  REFERENCES items_category(id)
);

CREATE TABLE items_extra (
  id               NUMBER(19) PRIMARY KEY,
  item_description VARCHAR2(1000),
  vat              BINARY_DOUBLE,
  last_cost_price  NUMBER(9,2),
  main_barcode     VARCHAR2(20),
  supplier_code    VARCHAR2(60),
  weight           NUMBER(9,2),
  um               VARCHAR2(10),
  CONSTRAINT fk_items_extra_core FOREIGN KEY (id) REFERENCES items_core(id) ON DELETE CASCADE
);

-- ------ View de transparenta verticala (JOIN dupa id) ------
CREATE OR REPLACE VIEW v_items AS
SELECT c.id, c.item_code, c.item_name, e.item_description,
       c.brand_id, c.season_id, c.item_type_id, c.category_id,
       e.vat, e.last_cost_price, e.main_barcode, e.supplier_code,
       e.weight, e.um, c.active
FROM   items_core c
       JOIN items_extra e ON e.id = c.id;

-- ------ Triggere INSTEAD OF pe V_ITEMS ------
CREATE OR REPLACE TRIGGER trg_v_items_ins
INSTEAD OF INSERT ON v_items
FOR EACH ROW
BEGIN
  INSERT INTO items_core (id, item_code, item_name, brand_id, season_id, item_type_id, category_id, active)
    VALUES (:NEW.id, :NEW.item_code, :NEW.item_name, :NEW.brand_id,
            :NEW.season_id, :NEW.item_type_id, :NEW.category_id, :NEW.active);
  INSERT INTO items_extra (id, item_description, vat, last_cost_price, main_barcode, supplier_code, weight, um)
    VALUES (:NEW.id, :NEW.item_description, :NEW.vat, :NEW.last_cost_price,
            :NEW.main_barcode, :NEW.supplier_code, :NEW.weight, :NEW.um);
END;
/

CREATE OR REPLACE TRIGGER trg_v_items_upd
INSTEAD OF UPDATE ON v_items
FOR EACH ROW
BEGIN
  UPDATE items_core SET
    item_code = :NEW.item_code, item_name = :NEW.item_name,
    brand_id = :NEW.brand_id, season_id = :NEW.season_id,
    item_type_id = :NEW.item_type_id, category_id = :NEW.category_id,
    active = :NEW.active
  WHERE id = :OLD.id;
  UPDATE items_extra SET
    item_description = :NEW.item_description, vat = :NEW.vat,
    last_cost_price = :NEW.last_cost_price, main_barcode = :NEW.main_barcode,
    supplier_code = :NEW.supplier_code, weight = :NEW.weight, um = :NEW.um
  WHERE id = :OLD.id;
END;
/

CREATE OR REPLACE TRIGGER trg_v_items_del
INSTEAD OF DELETE ON v_items
FOR EACH ROW
BEGIN
  DELETE FROM items_core WHERE id = :OLD.id;  -- ON DELETE CASCADE va sterge si items_extra
END;
/
