-- =============================================================================
-- 14_ddl_vanzari_fragments.sql
-- Schema VANZARI: 4 fragmente fizice (FISE_CLIENTI_RO/EXT + LINII_DOC_RO/EXT).
-- FK-urile cross-PDB (catre MV_CLIENTI si MV_ITEMS_CORE) le adaugam mai tarziu,
-- dupa ce MV-urile sunt populate (Task 12). FK-urile intra-PDB le adaugam acum.
-- =============================================================================

-- Fragment H primar 1: moneda = 'RON'
CREATE TABLE fise_clienti_ro (
  id                  NUMBER(19) PRIMARY KEY,
  nr_document         VARCHAR2(30) NOT NULL,
  nr_doc_initial      VARCHAR2(30),
  tip_doc             CHAR(1)      NOT NULL,
  doc_type_xrp        CHAR(3)      NOT NULL,
  data_doc_efectiva   DATE         NOT NULL,
  data_scad           DATE,
  semn                NUMBER(2)    NOT NULL,
  moneda              VARCHAR2(10) NOT NULL,
  amount_doc          NUMBER(17,2) NOT NULL,
  amount_doc_ron      NUMBER(17,2) NOT NULL,
  plata_prin          VARCHAR2(20),
  cod_client          VARCHAR2(60) NOT NULL,
  denumire_client     VARCHAR2(200) NOT NULL,
  clasa_client        VARCHAR2(20) NOT NULL,
  CONSTRAINT uk_fise_ro_doc UNIQUE (nr_document, doc_type_xrp),
  CONSTRAINT ck_fise_ro_mon CHECK (moneda = 'RON'),
  CONSTRAINT ck_fise_ro_tipdoc CHECK (tip_doc IN ('F','I')),
  CONSTRAINT ck_fise_ro_xrp CHECK (doc_type_xrp IN ('INV','PMT','CRM','PPM','REF','RPM','DRM','VRF')),
  CONSTRAINT ck_fise_ro_semn CHECK (semn IN (-1, 1))
);

-- Fragment H primar 2: moneda != 'RON' (EUR/CZK/USD)
CREATE TABLE fise_clienti_ext (
  id                  NUMBER(19) PRIMARY KEY,
  nr_document         VARCHAR2(30) NOT NULL,
  nr_doc_initial      VARCHAR2(30),
  tip_doc             CHAR(1)      NOT NULL,
  doc_type_xrp        CHAR(3)      NOT NULL,
  data_doc_efectiva   DATE         NOT NULL,
  data_scad           DATE,
  semn                NUMBER(2)    NOT NULL,
  moneda              VARCHAR2(10) NOT NULL,
  amount_doc          NUMBER(17,2) NOT NULL,
  amount_doc_ron      NUMBER(17,2) NOT NULL,
  plata_prin          VARCHAR2(20),
  cod_client          VARCHAR2(60) NOT NULL,
  denumire_client     VARCHAR2(200) NOT NULL,
  clasa_client        VARCHAR2(20) NOT NULL,
  CONSTRAINT uk_fise_ext_doc UNIQUE (nr_document, doc_type_xrp),
  CONSTRAINT ck_fise_ext_mon CHECK (moneda <> 'RON'),
  CONSTRAINT ck_fise_ext_tipdoc CHECK (tip_doc IN ('F','I')),
  CONSTRAINT ck_fise_ext_xrp CHECK (doc_type_xrp IN ('INV','PMT','CRM','PPM','REF','RPM','DRM','VRF')),
  CONSTRAINT ck_fise_ext_semn CHECK (semn IN (-1, 1))
);

-- Fragment H derivat 1: linii care apartin de FISE_CLIENTI_RO
CREATE TABLE linii_doc_ro (
  id                          NUMBER(19) PRIMARY KEY,
  doc_type_xrp                CHAR(3)      NOT NULL,
  nr_document                 VARCHAR2(30) NOT NULL,
  item_code                   VARCHAR2(50) NOT NULL,
  item_qty                    NUMBER(13,2),
  xrp_doc_valoare_fara_tva    NUMBER(9,2),
  xrp_doc_tva                 NUMBER(9,2),
  xrp_doc_procent_tva         NUMBER(9,2),
  xrp_doc_valoare_totala      NUMBER(9,2),
  xrp_linie_is_with_vat       VARCHAR2(40),
  xrp_linie_valoare_fara_tva  NUMBER(9,2),
  xrp_linie_tva               NUMBER(9,2),
  xrp_linie_proc_tva          NUMBER(9,2),
  CONSTRAINT fk_lin_ro_fise FOREIGN KEY (nr_document, doc_type_xrp)
    REFERENCES fise_clienti_ro(nr_document, doc_type_xrp)
);

-- Fragment H derivat 2: linii care apartin de FISE_CLIENTI_EXT
CREATE TABLE linii_doc_ext (
  id                          NUMBER(19) PRIMARY KEY,
  doc_type_xrp                CHAR(3)      NOT NULL,
  nr_document                 VARCHAR2(30) NOT NULL,
  item_code                   VARCHAR2(50) NOT NULL,
  item_qty                    NUMBER(13,2),
  xrp_doc_valoare_fara_tva    NUMBER(9,2),
  xrp_doc_tva                 NUMBER(9,2),
  xrp_doc_procent_tva         NUMBER(9,2),
  xrp_doc_valoare_totala      NUMBER(9,2),
  xrp_linie_is_with_vat       VARCHAR2(40),
  xrp_linie_valoare_fara_tva  NUMBER(9,2),
  xrp_linie_tva               NUMBER(9,2),
  xrp_linie_proc_tva          NUMBER(9,2),
  CONSTRAINT fk_lin_ext_fise FOREIGN KEY (nr_document, doc_type_xrp)
    REFERENCES fise_clienti_ext(nr_document, doc_type_xrp)
);
