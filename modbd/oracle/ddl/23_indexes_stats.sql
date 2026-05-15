-- =============================================================================
-- 23_indexes_stats.sql
-- Indecsi pe coloanele cele mai folosite in query-ul complex (filtre + joinuri)
-- + gather statistics ca CBO sa aiba estimari corecte.
-- =============================================================================

-- Indecsi pe fise_clienti_*
CREATE INDEX idx_fise_ro_data ON fise_clienti_ro(data_doc_efectiva);
CREATE INDEX idx_fise_ro_codcli ON fise_clienti_ro(cod_client);
CREATE INDEX idx_fise_ro_tip ON fise_clienti_ro(tip_doc);

CREATE INDEX idx_fise_ext_data ON fise_clienti_ext(data_doc_efectiva);
CREATE INDEX idx_fise_ext_codcli ON fise_clienti_ext(cod_client);
CREATE INDEX idx_fise_ext_tip ON fise_clienti_ext(tip_doc);

-- Indecsi pe linii_doc_* (FK composite e deja indexat prin constraint, dar item_code nu)
CREATE INDEX idx_lin_ro_item ON linii_doc_ro(item_code);
CREATE INDEX idx_lin_ext_item ON linii_doc_ext(item_code);

-- Gather statistici
EXEC DBMS_STATS.GATHER_SCHEMA_STATS(USER, cascade=>TRUE);
