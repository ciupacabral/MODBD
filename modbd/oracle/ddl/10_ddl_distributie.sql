-- =============================================================================
-- 10_ddl_distributie.sql
-- Schema DISTRIBUTIE (sgbd_distributie): CRM/comercial.
-- 8 tabele master:
--   ZONE                  -- zone comerciale (incl. self-FK pentru ierarhie)
--   AGENTI                -- agenti vanzari
--   CLIENTI               -- clienti (FK -> ZONE)
--   CLIENTI_CONTACTE      -- email-uri (FK -> CLIENTI)
--   INTERVALE_PLATA       -- termene de plata
--   INTERVALE_PLATA_ZILE  -- detalii termene (cheie compusa)
--   ZONE_AGENTI           -- M:N #1: zone <-> agenti (cu istoric)
--   ZONE_INTERVALE_PLATA  -- M:N #2: zone <-> termene (cu istoric)
-- =============================================================================


-- ============================================================================
-- ZONE: zone comerciale (Int/Ext) + ierarhie self-referentiala
-- ============================================================================
CREATE TABLE zone (
    id              NUMBER(19)
  , cod_zona        VARCHAR2(40)    NOT NULL
  , den_zona        VARCHAR2(80)    NOT NULL
  , tip_zona        VARCHAR2(10)    NOT NULL
  , parent_zona_id  NUMBER(19)
  , CONSTRAINT pk_zone
        PRIMARY KEY (id)
  , CONSTRAINT uk_zone_cod
        UNIQUE (cod_zona)
  , CONSTRAINT fk_zone_parent
        FOREIGN KEY (parent_zona_id) REFERENCES zone (id)
);


-- ============================================================================
-- AGENTI: agenti vanzari
-- ============================================================================
CREATE TABLE agenti (
    id          NUMBER(19)
  , cod_agent   VARCHAR2(20)    NOT NULL
  , nume_agent  VARCHAR2(100)   NOT NULL
  , email       VARCHAR2(200)
  , CONSTRAINT pk_agenti
        PRIMARY KEY (id)
  , CONSTRAINT uk_agenti_cod
        UNIQUE (cod_agent)
);


-- ============================================================================
-- CLIENTI: anonimizati CLI000001..CLI000010, alocati pe zone
-- ============================================================================
CREATE TABLE clienti (
    id               NUMBER(19)
  , cod_client       VARCHAR2(60)    NOT NULL
  , denumire_client  VARCHAR2(200)   NOT NULL
  , tip_client       VARCHAR2(12)    NOT NULL
  , id_zona          NUMBER(19)      NOT NULL
  , start_date       DATE            NOT NULL
  , end_date         DATE
  , CONSTRAINT pk_clienti
        PRIMARY KEY (id)
  , CONSTRAINT uk_clienti_cod
        UNIQUE (cod_client)
  , CONSTRAINT fk_clienti_zona
        FOREIGN KEY (id_zona) REFERENCES zone (id)
  , CONSTRAINT ck_clienti_dates
        CHECK (end_date IS NULL OR end_date > start_date)
);


-- ============================================================================
-- CLIENTI_CONTACTE: email-uri (fictive)
-- ============================================================================
CREATE TABLE clienti_contacte (
    cod_client    VARCHAR2(60)
  , email_client  VARCHAR2(1000)
  , email_agent   VARCHAR2(1000)
  , CONSTRAINT pk_contacte
        PRIMARY KEY (cod_client)
  , CONSTRAINT fk_contacte_client
        FOREIGN KEY (cod_client) REFERENCES clienti (cod_client)
);


-- ============================================================================
-- INTERVALE_PLATA: tipuri de termene de plata
-- ============================================================================
CREATE TABLE intervale_plata (
    id            NUMBER(19)
  , den_interval  VARCHAR2(60)   NOT NULL
  , CONSTRAINT pk_intpl
        PRIMARY KEY (id)
  , CONSTRAINT uk_intpl_den
        UNIQUE (den_interval)
);


-- ============================================================================
-- INTERVALE_PLATA_ZILE: detalii termene (cheie compusa interval + perioada)
-- ============================================================================
CREATE TABLE intervale_plata_zile (
    id_interval  NUMBER(19)     NOT NULL
  , per_zile     VARCHAR2(40)   NOT NULL
  , zile_start   NUMBER(10)     NOT NULL
  , zile_end     NUMBER(10)
  , CONSTRAINT pk_intpl_zile
        PRIMARY KEY (id_interval, per_zile)
  , CONSTRAINT fk_intpl_zile
        FOREIGN KEY (id_interval) REFERENCES intervale_plata (id)
);


-- ============================================================================
-- ZONE_AGENTI: M:N #1 (zone <-> agenti) cu istoric prin start_date / end_date
-- ============================================================================
CREATE TABLE zone_agenti (
    id          NUMBER(19)
  , id_zona     NUMBER(19)   NOT NULL
  , id_agent    NUMBER(19)   NOT NULL
  , start_date  DATE         NOT NULL
  , end_date    DATE
  , CONSTRAINT pk_zone_agenti
        PRIMARY KEY (id)
  , CONSTRAINT fk_za_zona
        FOREIGN KEY (id_zona) REFERENCES zone (id)
  , CONSTRAINT fk_za_agent
        FOREIGN KEY (id_agent) REFERENCES agenti (id)
  , CONSTRAINT ck_za_dates
        CHECK (end_date IS NULL OR end_date > start_date)
);


-- ============================================================================
-- ZONE_INTERVALE_PLATA: M:N #2 (zone <-> intervale plata) cu istoric
-- ============================================================================
CREATE TABLE zone_intervale_plata (
    id           NUMBER(19)
  , id_zona      NUMBER(19)   NOT NULL
  , id_interval  NUMBER(19)   NOT NULL
  , start_date   DATE         NOT NULL
  , end_date     DATE
  , CONSTRAINT pk_zone_intpl
        PRIMARY KEY (id)
  , CONSTRAINT fk_zip_zona
        FOREIGN KEY (id_zona) REFERENCES zone (id)
  , CONSTRAINT fk_zip_interval
        FOREIGN KEY (id_interval) REFERENCES intervale_plata (id)
  , CONSTRAINT ck_zip_dates
        CHECK (end_date IS NULL OR end_date > start_date)
);
