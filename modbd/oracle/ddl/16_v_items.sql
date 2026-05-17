-- =============================================================================
-- 16_v_items.sql
-- Transparenta verticala pentru fragmentarea BEA pe ITEMS (din PDB CATALOG).
--   - V_ITEMS = view de transparenta = JOIN intre ITEMS_CORE si ITEMS_EXTRA
--   - 3 triggere INSTEAD OF (INSERT / UPDATE / DELETE) pe V_ITEMS
--
-- Acest fisier face parte din layerul de transparenta (impreuna cu 17 pentru
-- VANZARI). Se ruleaza dupa ce ITEMS_CORE/ITEMS_EXTRA exista (vezi 12).
-- =============================================================================


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
