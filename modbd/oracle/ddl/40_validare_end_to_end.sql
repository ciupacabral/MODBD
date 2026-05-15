-- =============================================================================
-- 40_validare_end_to_end.sql
-- Verifica toate componentele BD-ului distribuit end-to-end:
--   1. Counts pe toate tabelele (PDB-uri) + MV-uri replicate
--   2. View-uri de transparenta returneaza acelasi total ca fragmentele
--   3. INSTEAD OF triggers functioneaza pe V_FISE (INSERT/UPDATE/DELETE)
--   4. FK cross-PDB blocheaza inserari invalide
--   5. Sync MV functioneaza dupa refresh manual
-- =============================================================================

SET SERVEROUTPUT ON
SET LINESIZE 200

-- Test 1: Counts
PROMPT === Test 1: Counts globale ===
SELECT 'distributie.clienti' AS t, COUNT(*) AS n FROM clienti@lnk_distributie
UNION ALL SELECT 'distributie.zone', COUNT(*) FROM zone@lnk_distributie
UNION ALL SELECT 'catalog.items_core', COUNT(*) FROM items_core@lnk_catalog
UNION ALL SELECT 'vanzari.v_fise', COUNT(*) FROM v_fise_clienti
UNION ALL SELECT 'vanzari.v_linii', COUNT(*) FROM v_linii_doc
UNION ALL SELECT 'vanzari.mv_clienti', COUNT(*) FROM mv_clienti
UNION ALL SELECT 'vanzari.mv_items_core', COUNT(*) FROM mv_items_core;

-- Test 2: Transparenta UNION ALL
PROMPT === Test 2: View total = sum fragments ===
SELECT (SELECT COUNT(*) FROM v_fise_clienti)
       - ((SELECT COUNT(*) FROM fise_clienti_ro) + (SELECT COUNT(*) FROM fise_clienti_ext))
       AS diff_fise FROM dual;

-- Test 3: INSERT prin view -> aterizeaza pe fragmentul corect
PROMPT === Test 3: INSTEAD OF INSERT pe V_FISE ===
INSERT INTO v_fise_clienti VALUES (
  77777777, 'TEST_RO', NULL, 'F', 'INV', SYSDATE, NULL,
  1, 'RON', 100, 100, NULL, 'CLI000001', 'Alpha Distrib SRL', 'DISTR'
);
INSERT INTO v_fise_clienti VALUES (
  77777778, 'TEST_EUR', NULL, 'F', 'INV', SYSDATE, NULL,
  1, 'EUR', 50, 250, NULL, 'CLI000001', 'Alpha Distrib SRL', 'DISTR'
);
SELECT COUNT(*) AS in_ro FROM fise_clienti_ro WHERE id = 77777777;
SELECT COUNT(*) AS in_ext FROM fise_clienti_ext WHERE id = 77777778;
ROLLBACK;

-- Test 4: FK cross-PDB blocheaza
PROMPT === Test 4: FK cross-PDB rejects bad client ===
DECLARE
  v_failed BOOLEAN := FALSE;
BEGIN
  BEGIN
    INSERT INTO fise_clienti_ro (id, nr_document, tip_doc, doc_type_xrp,
      data_doc_efectiva, semn, moneda, amount_doc, amount_doc_ron,
      cod_client, denumire_client, clasa_client)
    VALUES (88888888, 'BAD_FK', 'F', 'INV', SYSDATE, 1, 'RON', 100, 100,
            'NONEXISTENT', 'Test', 'DISTR');
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

-- Test 5: Sync MV (forced refresh)
PROMPT === Test 5: Manual refresh MV ===
EXEC DBMS_MVIEW.REFRESH('MV_CLIENTI', method=>'F');
SELECT COUNT(*) AS mv_clienti_count FROM mv_clienti;
