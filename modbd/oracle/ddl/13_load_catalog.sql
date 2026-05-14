-- =============================================================================
-- 13_load_catalog.sql
-- Incarca CATALOG: 4 lookup-uri + ITEMS split vertical in CORE/EXTRA.
-- ITEMS.csv contine toate 15 coloane; le distribuim in cele 2 fragmente prin
-- 2 INSERT-uri din acelasi external table.
-- LRTRIM strips trailing \r from CRLF endings.
-- NOLOGFILE/NOBADFILE/NODISCARDFILE because /csv mount is read-only.
-- Note: external table column NAMES are arbitrary; CSV is read positionally.
-- =============================================================================

-- BRANDS
CREATE TABLE ext_brands (
  id NUMBER(19), code VARCHAR2(3), brand VARCHAR2(50), description VARCHAR2(300)
)
ORGANIZATION EXTERNAL (
  TYPE ORACLE_LOADER DEFAULT DIRECTORY csv_dir
  ACCESS PARAMETERS (
    RECORDS DELIMITED BY NEWLINE
    CHARACTERSET UTF8
    NOLOGFILE NOBADFILE NODISCARDFILE
    SKIP 1
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LRTRIM
    MISSING FIELD VALUES ARE NULL
  )
  LOCATION ('BRANDS.csv')
) REJECT LIMIT UNLIMITED;

INSERT INTO brands (id, code, brand, description)
SELECT id, code,
       NULLIF(brand, 'NULL'),
       NULLIF(description, 'NULL')
FROM ext_brands;
DROP TABLE ext_brands;

-- ITEMS_CATEGORY (CSV: id, code, category, name)
CREATE TABLE ext_items_cat (
  id NUMBER(19), code VARCHAR2(2), category VARCHAR2(50), name VARCHAR2(50)
)
ORGANIZATION EXTERNAL (
  TYPE ORACLE_LOADER DEFAULT DIRECTORY csv_dir
  ACCESS PARAMETERS (
    RECORDS DELIMITED BY NEWLINE
    CHARACTERSET UTF8
    NOLOGFILE NOBADFILE NODISCARDFILE
    SKIP 1
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LRTRIM
    MISSING FIELD VALUES ARE NULL
  )
  LOCATION ('ITEMS_CATEGORY.csv')
) REJECT LIMIT UNLIMITED;

INSERT INTO items_category SELECT * FROM ext_items_cat;
DROP TABLE ext_items_cat;

-- ITEMS_TYPE
CREATE TABLE ext_items_type (
  id NUMBER(19), code VARCHAR2(4), item_type VARCHAR2(200), description VARCHAR2(600)
)
ORGANIZATION EXTERNAL (
  TYPE ORACLE_LOADER DEFAULT DIRECTORY csv_dir
  ACCESS PARAMETERS (
    RECORDS DELIMITED BY NEWLINE
    CHARACTERSET UTF8
    NOLOGFILE NOBADFILE NODISCARDFILE
    SKIP 1
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LRTRIM
    MISSING FIELD VALUES ARE NULL
  )
  LOCATION ('ITEMS_TYPE.csv')
) REJECT LIMIT UNLIMITED;

INSERT INTO items_type (id, code, item_type, description)
SELECT id, code, item_type, NULLIF(description, 'NULL') FROM ext_items_type;
DROP TABLE ext_items_type;

-- ITEMS_SEASONS (CSV header is 'YEAR' but we name the column season_year in the ext table)
-- Oracle reads CSV positionally — column names in the table definition don't need to match CSV header.
CREATE TABLE ext_items_seasons (
  id NUMBER(19), code VARCHAR2(120), description VARCHAR2(40),
  season_year VARCHAR2(8), active NUMBER(10)
)
ORGANIZATION EXTERNAL (
  TYPE ORACLE_LOADER DEFAULT DIRECTORY csv_dir
  ACCESS PARAMETERS (
    RECORDS DELIMITED BY NEWLINE
    CHARACTERSET UTF8
    NOLOGFILE NOBADFILE NODISCARDFILE
    SKIP 1
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LRTRIM
    MISSING FIELD VALUES ARE NULL
  )
  LOCATION ('ITEMS_SEASONS.csv')
) REJECT LIMIT UNLIMITED;

INSERT INTO items_seasons (id, code, description, season_year, active)
SELECT id, code, description, season_year, active FROM ext_items_seasons;
DROP TABLE ext_items_seasons;

-- ITEMS (15 coloane CSV → split CORE 8 + EXTRA 8 share id)
-- All numeric/decimal columns declared as VARCHAR2 to handle 'NULL' strings safely;
-- we cast in the INSERT.
CREATE TABLE ext_items (
  id NUMBER(19), item_code VARCHAR2(50), item_name VARCHAR2(350),
  item_description VARCHAR2(1000),
  brand_id VARCHAR2(20), season_id VARCHAR2(20),
  item_type_id VARCHAR2(20), category_id VARCHAR2(20),
  vat VARCHAR2(40), last_cost_price VARCHAR2(40),
  main_barcode VARCHAR2(20), supplier_code VARCHAR2(60),
  weight VARCHAR2(40), um VARCHAR2(10), active VARCHAR2(10)
)
ORGANIZATION EXTERNAL (
  TYPE ORACLE_LOADER DEFAULT DIRECTORY csv_dir
  ACCESS PARAMETERS (
    RECORDS DELIMITED BY NEWLINE
    CHARACTERSET UTF8
    NOLOGFILE NOBADFILE NODISCARDFILE
    SKIP 1
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LRTRIM
    MISSING FIELD VALUES ARE NULL
  )
  LOCATION ('ITEMS.csv')
) REJECT LIMIT UNLIMITED;

-- Populez CORE (identity + classification: 8 cols including id)
INSERT INTO items_core (id, item_code, item_name, brand_id, season_id, item_type_id, category_id, active)
SELECT id, item_code, item_name,
       CAST(NULLIF(brand_id,    'NULL') AS NUMBER(19)),
       CAST(NULLIF(season_id,   'NULL') AS NUMBER(19)),
       CAST(NULLIF(item_type_id,'NULL') AS NUMBER(19)),
       CAST(NULLIF(category_id, 'NULL') AS NUMBER(19)),
       CAST(NULLIF(active, 'NULL') AS NUMBER)
FROM ext_items;

-- Populez EXTRA (commercial + physical: 8 cols including id)
INSERT INTO items_extra (id, item_description, vat, last_cost_price, main_barcode, supplier_code, weight, um)
SELECT id,
       NULLIF(item_description, 'NULL'),
       CAST(NULLIF(vat, 'NULL') AS BINARY_DOUBLE),
       CAST(NULLIF(last_cost_price, 'NULL') AS NUMBER(9,2)),
       NULLIF(main_barcode, 'NULL'),
       NULLIF(supplier_code, 'NULL'),
       CAST(NULLIF(weight, 'NULL') AS NUMBER(9,2)),
       NULLIF(um, 'NULL')
FROM ext_items;
DROP TABLE ext_items;

COMMIT;
