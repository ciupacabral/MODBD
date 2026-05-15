-- =============================================================================
-- 15_load_vanzari.sql
-- Incarca cele 4 fragmente fizice ale VANZARI prin 2 external tables:
--  - ext_fise_all (DOCS_HEADERS.csv) -> INSERT cu WHERE moneda='RON' / <>'RON'
--  - ext_linii_all (DOCS_LINES.csv) -> INSERT cu join pe nr_doc+doc_type_xrp
--    catre fragmentul de fise corespunzator
-- LRTRIM strips trailing \r from CRLF. NOLOGFILE/NOBADFILE/NODISCARDFILE since
-- /csv mount is read-only.
-- =============================================================================

-- External table pentru documente
CREATE TABLE ext_fise_all (
  id                  NUMBER(19),
  nr_document         VARCHAR2(30),
  nr_doc_initial      VARCHAR2(30),
  tip_doc             CHAR(1),
  doc_type_xrp        CHAR(3),
  data_doc_efectiva   VARCHAR2(20),
  data_scad           VARCHAR2(20),
  semn                NUMBER(2),
  moneda              VARCHAR2(10),
  amount_doc          NUMBER(17,2),
  amount_doc_ron      NUMBER(17,2),
  plata_prin          VARCHAR2(20),
  cod_client          VARCHAR2(60),
  denumire_client     VARCHAR2(200),
  clasa_client        VARCHAR2(20)
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
  LOCATION ('DOCS_HEADERS.csv')
) REJECT LIMIT UNLIMITED;

-- INSERT in FISE_CLIENTI_RO (filter moneda='RON')
INSERT INTO fise_clienti_ro (id, nr_document, nr_doc_initial, tip_doc, doc_type_xrp,
                              data_doc_efectiva, data_scad, semn, moneda,
                              amount_doc, amount_doc_ron, plata_prin,
                              cod_client, denumire_client, clasa_client)
SELECT id, nr_document, NULLIF(nr_doc_initial, 'NULL'), tip_doc, doc_type_xrp,
       TO_DATE(data_doc_efectiva, 'YYYY-MM-DD'),
       CASE WHEN data_scad='NULL' THEN NULL ELSE TO_DATE(data_scad, 'YYYY-MM-DD') END,
       semn, moneda, amount_doc, amount_doc_ron,
       NULLIF(plata_prin, 'NULL'),
       cod_client, denumire_client, clasa_client
FROM ext_fise_all
WHERE moneda = 'RON';

-- INSERT in FISE_CLIENTI_EXT (filter moneda<>'RON')
INSERT INTO fise_clienti_ext (id, nr_document, nr_doc_initial, tip_doc, doc_type_xrp,
                               data_doc_efectiva, data_scad, semn, moneda,
                               amount_doc, amount_doc_ron, plata_prin,
                               cod_client, denumire_client, clasa_client)
SELECT id, nr_document, NULLIF(nr_doc_initial, 'NULL'), tip_doc, doc_type_xrp,
       TO_DATE(data_doc_efectiva, 'YYYY-MM-DD'),
       CASE WHEN data_scad='NULL' THEN NULL ELSE TO_DATE(data_scad, 'YYYY-MM-DD') END,
       semn, moneda, amount_doc, amount_doc_ron,
       NULLIF(plata_prin, 'NULL'),
       cod_client, denumire_client, clasa_client
FROM ext_fise_all
WHERE moneda <> 'RON';

DROP TABLE ext_fise_all;

-- External table pentru linii
CREATE TABLE ext_linii_all (
  id                          NUMBER(19),
  doc_type_xrp                CHAR(3),
  nr_document                 VARCHAR2(30),
  item_code                   VARCHAR2(50),
  item_qty                    NUMBER(13,2),
  xrp_doc_valoare_fara_tva    NUMBER(9,2),
  xrp_doc_tva                 NUMBER(9,2),
  xrp_doc_procent_tva         NUMBER(9,2),
  xrp_doc_valoare_totala      NUMBER(9,2),
  xrp_linie_is_with_vat       VARCHAR2(40),
  xrp_linie_valoare_fara_tva  NUMBER(9,2),
  xrp_linie_tva               NUMBER(9,2),
  xrp_linie_proc_tva          NUMBER(9,2)
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
  LOCATION ('DOCS_LINES.csv')
) REJECT LIMIT UNLIMITED;

-- INSERT in LINII_DOC_RO (linii al caror header e in fise_clienti_ro)
INSERT INTO linii_doc_ro
SELECT l.* FROM ext_linii_all l
WHERE EXISTS (
  SELECT 1 FROM fise_clienti_ro f
  WHERE f.nr_document = l.nr_document AND f.doc_type_xrp = l.doc_type_xrp
);

-- INSERT in LINII_DOC_EXT (linii al caror header e in fise_clienti_ext)
INSERT INTO linii_doc_ext
SELECT l.* FROM ext_linii_all l
WHERE EXISTS (
  SELECT 1 FROM fise_clienti_ext f
  WHERE f.nr_document = l.nr_document AND f.doc_type_xrp = l.doc_type_xrp
);

DROP TABLE ext_linii_all;
COMMIT;
