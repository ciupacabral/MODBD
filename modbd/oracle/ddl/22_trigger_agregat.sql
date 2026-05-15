-- =============================================================================
-- 22_trigger_agregat.sql
-- Propozitie de integritate cu agregat (curs cap. 3.4): suma valorilor de pe
-- liniile unui document trebuie sa fie egala (toleranta 0.01) cu valoarea
-- totala a documentului. Implementare: trigger AFTER STATEMENT pe linii_doc_*.
-- =============================================================================

CREATE OR REPLACE TRIGGER trg_coerenta_sum_ro
AFTER INSERT OR UPDATE OR DELETE ON linii_doc_ro
DECLARE
  CURSOR c IS
    SELECT f.nr_document, f.doc_type_xrp,
           f.amount_doc       AS doc_total,
           SUM(l.xrp_linie_valoare_fara_tva + l.xrp_linie_tva) AS sum_linii
    FROM fise_clienti_ro f
         JOIN linii_doc_ro l ON (l.nr_document, l.doc_type_xrp) = (f.nr_document, f.doc_type_xrp)
    GROUP BY f.nr_document, f.doc_type_xrp, f.amount_doc
    HAVING ABS(f.amount_doc - SUM(l.xrp_linie_valoare_fara_tva + l.xrp_linie_tva)) > 0.01;
BEGIN
  FOR r IN c LOOP
    RAISE_APPLICATION_ERROR(-20001,
      'Incoerenta suma pe ' || r.nr_document || '/' || r.doc_type_xrp ||
      ' (doc=' || r.doc_total || ' vs sum_linii=' || r.sum_linii || ')');
  END LOOP;
END;
/

CREATE OR REPLACE TRIGGER trg_coerenta_sum_ext
AFTER INSERT OR UPDATE OR DELETE ON linii_doc_ext
DECLARE
  CURSOR c IS
    SELECT f.nr_document, f.doc_type_xrp,
           f.amount_doc       AS doc_total,
           SUM(l.xrp_linie_valoare_fara_tva + l.xrp_linie_tva) AS sum_linii
    FROM fise_clienti_ext f
         JOIN linii_doc_ext l ON (l.nr_document, l.doc_type_xrp) = (f.nr_document, f.doc_type_xrp)
    GROUP BY f.nr_document, f.doc_type_xrp, f.amount_doc
    HAVING ABS(f.amount_doc - SUM(l.xrp_linie_valoare_fara_tva + l.xrp_linie_tva)) > 0.01;
BEGIN
  FOR r IN c LOOP
    RAISE_APPLICATION_ERROR(-20002,
      'Incoerenta suma EXT pe ' || r.nr_document || '/' || r.doc_type_xrp);
  END LOOP;
END;
/
