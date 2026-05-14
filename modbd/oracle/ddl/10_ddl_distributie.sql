-- =============================================================================
-- 10_ddl_distributie.sql
-- Schema DISTRIBUTIE (sgbd_distributie): CRM/comercial.
-- 8 tabele: ZONE, AGENTI, CLIENTI, CLIENTI_CONTACTE, INTERVALE_PLATA,
--          INTERVALE_PLATA_ZILE, ZONE_AGENTI (M:N), ZONE_INTERVALE_PLATA (M:N).
-- =============================================================================

CREATE TABLE zone (
  id              NUMBER(19) PRIMARY KEY,
  cod_zona        VARCHAR2(40)  NOT NULL,
  den_zona        VARCHAR2(80)  NOT NULL,
  tip_zona        VARCHAR2(10)  NOT NULL,
  parent_zona_id  NUMBER(19),
  CONSTRAINT uk_zone_cod UNIQUE (cod_zona),
  CONSTRAINT fk_zone_parent FOREIGN KEY (parent_zona_id) REFERENCES zone(id)
);

CREATE TABLE agenti (
  id          NUMBER(19) PRIMARY KEY,
  cod_agent   VARCHAR2(20)  NOT NULL,
  nume_agent  VARCHAR2(100) NOT NULL,
  email       VARCHAR2(200),
  CONSTRAINT uk_agenti_cod UNIQUE (cod_agent)
);

CREATE TABLE clienti (
  id               NUMBER(19) PRIMARY KEY,
  cod_client       VARCHAR2(60)  NOT NULL,
  denumire_client  VARCHAR2(200) NOT NULL,
  tip_client       VARCHAR2(12)  NOT NULL,
  id_zona          NUMBER(19)    NOT NULL,
  start_date       DATE          NOT NULL,
  end_date         DATE,
  CONSTRAINT uk_clienti_cod UNIQUE (cod_client),
  CONSTRAINT fk_clienti_zona FOREIGN KEY (id_zona) REFERENCES zone(id),
  CONSTRAINT ck_clienti_dates CHECK (end_date IS NULL OR end_date > start_date)
);

CREATE TABLE clienti_contacte (
  cod_client    VARCHAR2(60)   PRIMARY KEY,
  email_client  VARCHAR2(1000),
  email_agent   VARCHAR2(1000),
  CONSTRAINT fk_contacte_client FOREIGN KEY (cod_client) REFERENCES clienti(cod_client)
);

CREATE TABLE intervale_plata (
  id            NUMBER(19) PRIMARY KEY,
  den_interval  VARCHAR2(60) NOT NULL,
  CONSTRAINT uk_intpl_den UNIQUE (den_interval)
);

CREATE TABLE intervale_plata_zile (
  id_interval  NUMBER(19)   NOT NULL,
  per_zile     VARCHAR2(40) NOT NULL,
  zile_start   NUMBER(10)   NOT NULL,
  zile_end     NUMBER(10),
  CONSTRAINT pk_intpl_zile PRIMARY KEY (id_interval, per_zile),
  CONSTRAINT fk_intpl_zile FOREIGN KEY (id_interval) REFERENCES intervale_plata(id)
);

CREATE TABLE zone_agenti (
  id          NUMBER(19) PRIMARY KEY,
  id_zona     NUMBER(19) NOT NULL,
  id_agent    NUMBER(19) NOT NULL,
  start_date  DATE       NOT NULL,
  end_date    DATE,
  CONSTRAINT fk_za_zona FOREIGN KEY (id_zona) REFERENCES zone(id),
  CONSTRAINT fk_za_agent FOREIGN KEY (id_agent) REFERENCES agenti(id),
  CONSTRAINT ck_za_dates CHECK (end_date IS NULL OR end_date > start_date)
);

CREATE TABLE zone_intervale_plata (
  id           NUMBER(19) PRIMARY KEY,
  id_zona      NUMBER(19) NOT NULL,
  id_interval  NUMBER(19) NOT NULL,
  start_date   DATE       NOT NULL,
  end_date     DATE,
  CONSTRAINT fk_zip_zona FOREIGN KEY (id_zona) REFERENCES zone(id),
  CONSTRAINT fk_zip_interval FOREIGN KEY (id_interval) REFERENCES intervale_plata(id),
  CONSTRAINT ck_zip_dates CHECK (end_date IS NULL OR end_date > start_date)
);
