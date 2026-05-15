-- =============================================================================
-- 30_query_complex.sql
-- Cererea complexa a proiectului:
--   "Top 10 agenti dupa valoare vanduta in 2024,
--    defalcat pe zona si categorie de produs."
--
-- Query-ul atinge toate cele 3 PDB-uri:
--   - DISTRIBUTIE : AGENTI, ZONE_AGENTI            (prin DB link)
--   - CATALOG     : MV_ITEMS_CORE, MV_ITEMS_CATEGORY (local, via MV-uri)
--   - VANZARI     : V_FISE_CLIENTI, V_LINII_DOC    (local, via view-uri)
--
-- Sectiuni:
--   1. Rezultatul query-ului (top 10 randuri)
--   2. EXPLAIN PLAN cu /*+ RULE */         (RBO, Ingres-like)
--   3. EXPLAIN PLAN default                (CBO, System R-like)
--   4. EXPLAIN PLAN cu /*+ DRIVING_SITE */ (CBO distribuit, System R*-like)
-- =============================================================================


SET LINESIZE 200
SET PAGESIZE 100


-- ============================================================================
-- 1. Query simplu: verificam ca returneaza rezultate reale
-- ============================================================================
PROMPT === 1. Query results ===

SELECT
    a.nume_agent
  , z.den_zona
  , c.name                                  AS categorie
  , SUM(ld.xrp_linie_valoare_fara_tva)      AS total_2024
FROM   v_fise_clienti  f
       JOIN v_linii_doc  ld
            ON  ld.nr_document  = f.nr_document
            AND ld.doc_type_xrp = f.doc_type_xrp
       JOIN mv_clienti  cli
            ON  cli.cod_client = f.cod_client
       JOIN mv_zone  z
            ON  z.id = cli.id_zona
       JOIN zone_agenti@lnk_distributie  za
            ON  za.id_zona = cli.id_zona
            AND f.data_doc_efectiva BETWEEN za.start_date
                                        AND NVL(za.end_date, DATE '9999-12-31')
       JOIN agenti@lnk_distributie  a
            ON  a.id = za.id_agent
       JOIN mv_items_core  ic
            ON  ic.item_code = ld.item_code
       JOIN mv_items_category  c
            ON  c.id = ic.category_id
WHERE  f.tip_doc           = 'F'
  AND  f.data_doc_efectiva >= DATE '2024-01-01'
  AND  f.data_doc_efectiva <  DATE '2025-01-01'
GROUP BY
    a.nume_agent
  , z.den_zona
  , c.name
ORDER BY
    total_2024 DESC
FETCH FIRST 10 ROWS ONLY;


-- ============================================================================
-- 2. Plan RBO (HINT /*+ RULE */) -- Ingres-like, heuristic
-- ============================================================================
PROMPT === 2. Plan RBO (HINT /*+ RULE */) ===

EXPLAIN PLAN SET STATEMENT_ID = 'Q_RBO' FOR
SELECT /*+ RULE */
    a.nume_agent
  , z.den_zona
  , c.name                                  AS categorie
  , SUM(ld.xrp_linie_valoare_fara_tva)      AS total_2024
FROM   v_fise_clienti  f
       JOIN v_linii_doc  ld
            ON  ld.nr_document  = f.nr_document
            AND ld.doc_type_xrp = f.doc_type_xrp
       JOIN mv_clienti  cli
            ON  cli.cod_client = f.cod_client
       JOIN mv_zone  z
            ON  z.id = cli.id_zona
       JOIN zone_agenti@lnk_distributie  za
            ON  za.id_zona = cli.id_zona
            AND f.data_doc_efectiva BETWEEN za.start_date
                                        AND NVL(za.end_date, DATE '9999-12-31')
       JOIN agenti@lnk_distributie  a
            ON  a.id = za.id_agent
       JOIN mv_items_core  ic
            ON  ic.item_code = ld.item_code
       JOIN mv_items_category  c
            ON  c.id = ic.category_id
WHERE  f.tip_doc           = 'F'
  AND  f.data_doc_efectiva >= DATE '2024-01-01'
  AND  f.data_doc_efectiva <  DATE '2025-01-01'
GROUP BY
    a.nume_agent
  , z.den_zona
  , c.name
ORDER BY
    total_2024 DESC
FETCH FIRST 10 ROWS ONLY;

SELECT plan_table_output
FROM   TABLE(DBMS_XPLAN.DISPLAY(NULL, 'Q_RBO', 'BASIC +ROWS +COST'));


-- ============================================================================
-- 3. Plan CBO default -- System R-like, cost-based dynamic programming
-- ============================================================================
PROMPT === 3. Plan CBO default ===

EXPLAIN PLAN SET STATEMENT_ID = 'Q_CBO' FOR
SELECT
    a.nume_agent
  , z.den_zona
  , c.name                                  AS categorie
  , SUM(ld.xrp_linie_valoare_fara_tva)      AS total_2024
FROM   v_fise_clienti  f
       JOIN v_linii_doc  ld
            ON  ld.nr_document  = f.nr_document
            AND ld.doc_type_xrp = f.doc_type_xrp
       JOIN mv_clienti  cli
            ON  cli.cod_client = f.cod_client
       JOIN mv_zone  z
            ON  z.id = cli.id_zona
       JOIN zone_agenti@lnk_distributie  za
            ON  za.id_zona = cli.id_zona
            AND f.data_doc_efectiva BETWEEN za.start_date
                                        AND NVL(za.end_date, DATE '9999-12-31')
       JOIN agenti@lnk_distributie  a
            ON  a.id = za.id_agent
       JOIN mv_items_core  ic
            ON  ic.item_code = ld.item_code
       JOIN mv_items_category  c
            ON  c.id = ic.category_id
WHERE  f.tip_doc           = 'F'
  AND  f.data_doc_efectiva >= DATE '2024-01-01'
  AND  f.data_doc_efectiva <  DATE '2025-01-01'
GROUP BY
    a.nume_agent
  , z.den_zona
  , c.name
ORDER BY
    total_2024 DESC
FETCH FIRST 10 ROWS ONLY;

SELECT plan_table_output
FROM   TABLE(DBMS_XPLAN.DISPLAY(NULL, 'Q_CBO', 'BASIC +ROWS +COST'));


-- ============================================================================
-- 4. Plan CBO + DRIVING_SITE(a) -- System R*-like, forteaza assembly site remote
-- (intregul query e materializat in DISTRIBUTIE, datele locale sunt trase
--  prin link reverse spre site-ul AGENTI)
-- ============================================================================
PROMPT === 4. Plan CBO + DRIVING_SITE(a) (assembly remote) ===

EXPLAIN PLAN SET STATEMENT_ID = 'Q_DRV' FOR
SELECT /*+ DRIVING_SITE(a) */
    a.nume_agent
  , z.den_zona
  , c.name                                  AS categorie
  , SUM(ld.xrp_linie_valoare_fara_tva)      AS total_2024
FROM   v_fise_clienti  f
       JOIN v_linii_doc  ld
            ON  ld.nr_document  = f.nr_document
            AND ld.doc_type_xrp = f.doc_type_xrp
       JOIN mv_clienti  cli
            ON  cli.cod_client = f.cod_client
       JOIN mv_zone  z
            ON  z.id = cli.id_zona
       JOIN zone_agenti@lnk_distributie  za
            ON  za.id_zona = cli.id_zona
            AND f.data_doc_efectiva BETWEEN za.start_date
                                        AND NVL(za.end_date, DATE '9999-12-31')
       JOIN agenti@lnk_distributie  a
            ON  a.id = za.id_agent
       JOIN mv_items_core  ic
            ON  ic.item_code = ld.item_code
       JOIN mv_items_category  c
            ON  c.id = ic.category_id
WHERE  f.tip_doc           = 'F'
  AND  f.data_doc_efectiva >= DATE '2024-01-01'
  AND  f.data_doc_efectiva <  DATE '2025-01-01'
GROUP BY
    a.nume_agent
  , z.den_zona
  , c.name
ORDER BY
    total_2024 DESC
FETCH FIRST 10 ROWS ONLY;

SELECT plan_table_output
FROM   TABLE(DBMS_XPLAN.DISPLAY(NULL, 'Q_DRV', 'BASIC +ROWS +COST'));
