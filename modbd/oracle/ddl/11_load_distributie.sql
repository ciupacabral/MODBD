-- =============================================================================
-- 11_load_distributie.sql
-- Incarca cele 8 CSV-uri ale schemei DISTRIBUTIE prin external tables.
--
-- Convenții folosite în toate external tables:
--   - SKIP 1                  : sare peste header-ul CSV
--   - CHARACTERSET UTF8       : ignora BOM-ul UTF-8 de la inceput
--   - LRTRIM                  : strip \r trailing (CSV-uri cu line endings CRLF)
--   - NOLOGFILE NOBADFILE
--     NODISCARDFILE           : daca directorul CSV este read-only,
--                               loader-ul nu va incerca sa scrie log-uri acolo
--   - REJECT LIMIT UNLIMITED  : nu abandona daca apar randuri rejectate
--
-- Tratarea 'NULL' (string in CSV):
--   - pentru coloane numerice: CAST(NULLIF(col, 'NULL') AS NUMBER...)
--   - pentru coloane DATE   : CASE WHEN col='NULL' THEN NULL ELSE TO_DATE(col, ...) END
-- =============================================================================


-- ============================================================================
-- ZONE
-- ============================================================================
CREATE TABLE ext_zone (
    id              NUMBER(19)
  , cod_zona        VARCHAR2(40)
  , den_zona        VARCHAR2(80)
  , tip_zona        VARCHAR2(10)
  , parent_zona_id  VARCHAR2(20)
)
ORGANIZATION EXTERNAL (
    TYPE              ORACLE_LOADER
    DEFAULT DIRECTORY csv_dir
    ACCESS PARAMETERS (
        RECORDS DELIMITED BY NEWLINE
        CHARACTERSET UTF8
        NOLOGFILE NOBADFILE NODISCARDFILE
        SKIP 1
        FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LRTRIM
        MISSING FIELD VALUES ARE NULL
    )
    LOCATION ('ZONE.csv')
) REJECT LIMIT UNLIMITED;


INSERT INTO zone (
    id
  , cod_zona
  , den_zona
  , tip_zona
  , parent_zona_id
)
SELECT
    id
  , cod_zona
  , den_zona
  , tip_zona
  , CASE WHEN parent_zona_id = 'NULL' THEN NULL ELSE TO_NUMBER(parent_zona_id) END
FROM ext_zone;

DROP TABLE ext_zone;


-- ============================================================================
-- AGENTI
-- ============================================================================
CREATE TABLE ext_agenti (
    id          NUMBER(19)
  , cod_agent   VARCHAR2(20)
  , nume_agent  VARCHAR2(100)
  , email       VARCHAR2(200)
)
ORGANIZATION EXTERNAL (
    TYPE              ORACLE_LOADER
    DEFAULT DIRECTORY csv_dir
    ACCESS PARAMETERS (
        RECORDS DELIMITED BY NEWLINE
        CHARACTERSET UTF8
        NOLOGFILE NOBADFILE NODISCARDFILE
        SKIP 1
        FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LRTRIM
        MISSING FIELD VALUES ARE NULL
    )
    LOCATION ('AGENTI.csv')
) REJECT LIMIT UNLIMITED;


INSERT INTO agenti
SELECT *
FROM   ext_agenti;

DROP TABLE ext_agenti;


-- ============================================================================
-- CLIENTI
-- ============================================================================
CREATE TABLE ext_clienti (
    id               NUMBER(19)
  , cod_client       VARCHAR2(60)
  , denumire_client  VARCHAR2(200)
  , tip_client       VARCHAR2(12)
  , id_zona          NUMBER(19)
  , start_date       VARCHAR2(20)
  , end_date         VARCHAR2(20)
)
ORGANIZATION EXTERNAL (
    TYPE              ORACLE_LOADER
    DEFAULT DIRECTORY csv_dir
    ACCESS PARAMETERS (
        RECORDS DELIMITED BY NEWLINE
        CHARACTERSET UTF8
        NOLOGFILE NOBADFILE NODISCARDFILE
        SKIP 1
        FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LRTRIM
        MISSING FIELD VALUES ARE NULL
    )
    LOCATION ('CLIENTI.csv')
) REJECT LIMIT UNLIMITED;


INSERT INTO clienti (
    id
  , cod_client
  , denumire_client
  , tip_client
  , id_zona
  , start_date
  , end_date
)
SELECT
    id
  , cod_client
  , denumire_client
  , tip_client
  , id_zona
  , TO_DATE(start_date, 'YYYY-MM-DD')
  , CASE WHEN end_date = 'NULL' THEN NULL ELSE TO_DATE(end_date, 'YYYY-MM-DD') END
FROM ext_clienti;

DROP TABLE ext_clienti;


-- ============================================================================
-- CLIENTI_CONTACTE
-- ============================================================================
CREATE TABLE ext_contacte (
    cod_client    VARCHAR2(60)
  , email_client  VARCHAR2(1000)
  , email_agent   VARCHAR2(1000)
)
ORGANIZATION EXTERNAL (
    TYPE              ORACLE_LOADER
    DEFAULT DIRECTORY csv_dir
    ACCESS PARAMETERS (
        RECORDS DELIMITED BY NEWLINE
        CHARACTERSET UTF8
        NOLOGFILE NOBADFILE NODISCARDFILE
        SKIP 1
        FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LRTRIM
        MISSING FIELD VALUES ARE NULL
    )
    LOCATION ('CONTACTE.csv')
) REJECT LIMIT UNLIMITED;


INSERT INTO clienti_contacte
SELECT *
FROM   ext_contacte;

DROP TABLE ext_contacte;


-- ============================================================================
-- INTERVALE_PLATA
-- ============================================================================
CREATE TABLE ext_intpl (
    id            NUMBER(19)
  , den_interval  VARCHAR2(60)
)
ORGANIZATION EXTERNAL (
    TYPE              ORACLE_LOADER
    DEFAULT DIRECTORY csv_dir
    ACCESS PARAMETERS (
        RECORDS DELIMITED BY NEWLINE
        CHARACTERSET UTF8
        NOLOGFILE NOBADFILE NODISCARDFILE
        SKIP 1
        FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LRTRIM
        MISSING FIELD VALUES ARE NULL
    )
    LOCATION ('INTERVALE_PLATA.csv')
) REJECT LIMIT UNLIMITED;


INSERT INTO intervale_plata
SELECT *
FROM   ext_intpl;

DROP TABLE ext_intpl;


-- ============================================================================
-- INTERVALE_PLATA_ZILE
-- ============================================================================
CREATE TABLE ext_intpl_zile (
    id_interval  NUMBER(19)
  , per_zile     VARCHAR2(40)
  , zile_start   NUMBER(10)
  , zile_end     VARCHAR2(10)
)
ORGANIZATION EXTERNAL (
    TYPE              ORACLE_LOADER
    DEFAULT DIRECTORY csv_dir
    ACCESS PARAMETERS (
        RECORDS DELIMITED BY NEWLINE
        CHARACTERSET UTF8
        NOLOGFILE NOBADFILE NODISCARDFILE
        SKIP 1
        FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LRTRIM
        MISSING FIELD VALUES ARE NULL
    )
    LOCATION ('INTERVALE_PLATA_ZILE.csv')
) REJECT LIMIT UNLIMITED;


INSERT INTO intervale_plata_zile (
    id_interval
  , per_zile
  , zile_start
  , zile_end
)
SELECT
    id_interval
  , per_zile
  , zile_start
  , CASE WHEN zile_end = 'NULL' THEN NULL ELSE TO_NUMBER(zile_end) END
FROM ext_intpl_zile;

DROP TABLE ext_intpl_zile;


-- ============================================================================
-- ZONE_AGENTI (M:N #1: zone <-> agenti, cu istoric)
-- ============================================================================
CREATE TABLE ext_za (
    id          NUMBER(19)
  , id_zona     NUMBER(19)
  , id_agent    NUMBER(19)
  , start_date  VARCHAR2(20)
  , end_date    VARCHAR2(20)
)
ORGANIZATION EXTERNAL (
    TYPE              ORACLE_LOADER
    DEFAULT DIRECTORY csv_dir
    ACCESS PARAMETERS (
        RECORDS DELIMITED BY NEWLINE
        CHARACTERSET UTF8
        NOLOGFILE NOBADFILE NODISCARDFILE
        SKIP 1
        FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LRTRIM
        MISSING FIELD VALUES ARE NULL
    )
    LOCATION ('ZONE_AGENTI.csv')
) REJECT LIMIT UNLIMITED;


INSERT INTO zone_agenti (
    id
  , id_zona
  , id_agent
  , start_date
  , end_date
)
SELECT
    id
  , id_zona
  , id_agent
  , TO_DATE(start_date, 'YYYY-MM-DD')
  , CASE WHEN end_date = 'NULL' THEN NULL ELSE TO_DATE(end_date, 'YYYY-MM-DD') END
FROM ext_za;

DROP TABLE ext_za;


-- ============================================================================
-- ZONE_INTERVALE_PLATA (M:N #2: zone <-> intervale plata, cu istoric)
-- ============================================================================
CREATE TABLE ext_zip (
    id           NUMBER(19)
  , id_zona      NUMBER(19)
  , id_interval  NUMBER(19)
  , start_date   VARCHAR2(20)
  , end_date     VARCHAR2(20)
)
ORGANIZATION EXTERNAL (
    TYPE              ORACLE_LOADER
    DEFAULT DIRECTORY csv_dir
    ACCESS PARAMETERS (
        RECORDS DELIMITED BY NEWLINE
        CHARACTERSET UTF8
        NOLOGFILE NOBADFILE NODISCARDFILE
        SKIP 1
        FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LRTRIM
        MISSING FIELD VALUES ARE NULL
    )
    LOCATION ('ZONE_INTERVALE_PLATA.csv')
) REJECT LIMIT UNLIMITED;


INSERT INTO zone_intervale_plata (
    id
  , id_zona
  , id_interval
  , start_date
  , end_date
)
SELECT
    id
  , id_zona
  , id_interval
  , TO_DATE(start_date, 'YYYY-MM-DD')
  , CASE WHEN end_date = 'NULL' THEN NULL ELSE TO_DATE(end_date, 'YYYY-MM-DD') END
FROM ext_zip;

DROP TABLE ext_zip;


COMMIT;
