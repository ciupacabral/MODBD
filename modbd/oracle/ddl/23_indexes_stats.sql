-- =============================================================================
-- 23_indexes_stats.sql
-- Indecsi pe coloanele cele mai folosite in query-ul complex (filtre + joinuri)
-- + gather statistics ca CBO sa aiba estimari corecte de cardinalitate.
-- Pasul de pregatire inainte de demonstrarea optimizarii RBO/CBO (Task 16).
-- =============================================================================


-- ============================================================================
-- Indecsi pe FISE_CLIENTI_RO (fragment H primar, moneda='RON')
-- ============================================================================
CREATE INDEX idx_fise_ro_data
    ON fise_clienti_ro (data_doc_efectiva);

CREATE INDEX idx_fise_ro_codcli
    ON fise_clienti_ro (cod_client);

CREATE INDEX idx_fise_ro_tip
    ON fise_clienti_ro (tip_doc);


-- ============================================================================
-- Indecsi pe FISE_CLIENTI_EXT (fragment H primar, moneda <> 'RON')
-- ============================================================================
CREATE INDEX idx_fise_ext_data
    ON fise_clienti_ext (data_doc_efectiva);

CREATE INDEX idx_fise_ext_codcli
    ON fise_clienti_ext (cod_client);

CREATE INDEX idx_fise_ext_tip
    ON fise_clienti_ext (tip_doc);


-- ============================================================================
-- Indecsi pe LINII_DOC_RO / LINII_DOC_EXT
-- (FK composit pe nr_doc + doc_type_xrp e indexat automat prin constraint;
--  item_code nu e in FK composit, deci il indexam explicit pentru joinuri)
-- ============================================================================
CREATE INDEX idx_lin_ro_item
    ON linii_doc_ro (item_code);

CREATE INDEX idx_lin_ext_item
    ON linii_doc_ext (item_code);


-- ============================================================================
-- Gather statistici pe intregul schema (pentru CBO)
-- ============================================================================
BEGIN
    DBMS_STATS.GATHER_SCHEMA_STATS (
        ownname => USER
      , cascade => TRUE
    );
END;
/
