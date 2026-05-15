-- =============================================================================
-- 40_validare_end_to_end.sql
-- Verifica toate componentele BD-ului distribuit end-to-end:
--
--   Test 1: Counts globale (toate cele 3 PDB-uri + MV-uri replicate)
--   Test 2: View-urile de transparenta = suma fragmentelor (UNION ALL corect)
--   Test 3: INSTEAD OF trigger pe V_FISE_CLIENTI ruteaza dupa moneda
--   Test 4: FK cross-PDB blocheaza inserarile cu parinti inexistenti
--   Test 5: Sincronizare MV functioneaza dupa refresh manual
-- =============================================================================


SET SERVEROUTPUT ON
SET LINESIZE 200


-- ============================================================================
-- Test 1: Counts globale
-- ============================================================================
PROMPT === Test 1: Counts globale ===

SELECT 'distributie.clienti'   AS t, COUNT(*) AS n FROM clienti@lnk_distributie
UNION ALL
SELECT 'distributie.zone'      ,     COUNT(*)      FROM zone@lnk_distributie
UNION ALL
SELECT 'catalog.items_core'    ,     COUNT(*)      FROM items_core@lnk_catalog
UNION ALL
SELECT 'vanzari.v_fise'        ,     COUNT(*)      FROM v_fise_clienti
UNION ALL
SELECT 'vanzari.v_linii'       ,     COUNT(*)      FROM v_linii_doc
UNION ALL
SELECT 'vanzari.mv_clienti'    ,     COUNT(*)      FROM mv_clienti
UNION ALL
SELECT 'vanzari.mv_items_core' ,     COUNT(*)      FROM mv_items_core;


-- ============================================================================
-- Test 2: Transparenta UNION ALL (view = suma fragmentelor)
-- ============================================================================
PROMPT === Test 2: View total = sum fragments ===

SELECT
    (SELECT COUNT(*) FROM v_fise_clienti)
  - (
        (SELECT COUNT(*) FROM fise_clienti_ro)
      + (SELECT COUNT(*) FROM fise_clienti_ext)
    )                                                AS diff_fise
FROM dual;


-- ============================================================================
-- Test 3: INSTEAD OF INSERT pe V_FISE_CLIENTI ruteaza dupa moneda
-- ============================================================================
PROMPT === Test 3: INSTEAD OF INSERT pe V_FISE ===

INSERT INTO v_fise_clienti VALUES (
    77777777
  , 'TEST_RO'
  , NULL
  , 'F'
  , 'INV'
  , SYSDATE
  , NULL
  , 1
  , 'RON'
  , 100
  , 100
  , NULL
  , 'CLI000001'
  , 'Alpha Distrib SRL'
  , 'DISTR'
);

INSERT INTO v_fise_clienti VALUES (
    77777778
  , 'TEST_EUR'
  , NULL
  , 'F'
  , 'INV'
  , SYSDATE
  , NULL
  , 1
  , 'EUR'
  , 50
  , 250
  , NULL
  , 'CLI000001'
  , 'Alpha Distrib SRL'
  , 'DISTR'
);

SELECT COUNT(*) AS in_ro
FROM   fise_clienti_ro
WHERE  id = 77777777;

SELECT COUNT(*) AS in_ext
FROM   fise_clienti_ext
WHERE  id = 77777778;

ROLLBACK;


-- ============================================================================
-- Test 4: FK cross-PDB blocheaza inserarea cu client inexistent
-- (Trebuie sa ridice ORA-02291. Daca NU ridica, FK e dezactivat sau lipseste.)
-- ============================================================================
PROMPT === Test 4: FK cross-PDB rejects bad client ===

DECLARE
    v_failed BOOLEAN := FALSE;
BEGIN
    BEGIN
        INSERT INTO fise_clienti_ro (
            id
          , nr_document
          , tip_doc
          , doc_type_xrp
          , data_doc_efectiva
          , semn
          , moneda
          , amount_doc
          , amount_doc_ron
          , cod_client
          , denumire_client
          , clasa_client
        ) VALUES (
            88888888
          , 'BAD_FK'
          , 'F'
          , 'INV'
          , SYSDATE
          , 1
          , 'RON'
          , 100
          , 100
          , 'NONEXISTENT'
          , 'Test'
          , 'DISTR'
        );
    EXCEPTION
        WHEN OTHERS THEN
            v_failed := TRUE;
            DBMS_OUTPUT.PUT_LINE('FK OK: ' || SQLERRM);
    END;

    IF NOT v_failed THEN
        DBMS_OUTPUT.PUT_LINE('FAILED: insertul nu a fost respins!');
        ROLLBACK;
    END IF;
END;
/


-- ============================================================================
-- Test 5: Sync MV (forced refresh manual)
-- ============================================================================
PROMPT === Test 5: Manual refresh MV ===

EXEC DBMS_MVIEW.REFRESH('MV_CLIENTI', method => 'F');

SELECT COUNT(*) AS mv_clienti_count
FROM   mv_clienti;
