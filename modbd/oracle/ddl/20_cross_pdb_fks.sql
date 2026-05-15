-- =============================================================================
-- 20_cross_pdb_fks.sql
-- FK-uri locale catre MV-uri replicate, enforce constrangerile globale.
-- NOTE: FK-uri pe cod_client (fise_clienti_ro/ext) created in earlier task.
-- This script adds FK-uri pe item_code (linii_doc_ro/ext).
-- =============================================================================

-- Delete orphan rows (with non-existent item_codes) before adding FKs
DELETE FROM linii_doc_ro ldr WHERE NOT EXISTS (
  SELECT 1 FROM mv_items_core mic WHERE mic.item_code = ldr.item_code
);

DELETE FROM linii_doc_ext lde WHERE NOT EXISTS (
  SELECT 1 FROM mv_items_core mic WHERE mic.item_code = lde.item_code
);

COMMIT;

-- Add FK constraints
ALTER TABLE linii_doc_ro
  ADD CONSTRAINT fk_lin_ro_item
  FOREIGN KEY (item_code) REFERENCES mv_items_core(item_code);

ALTER TABLE linii_doc_ext
  ADD CONSTRAINT fk_lin_ext_item
  FOREIGN KEY (item_code) REFERENCES mv_items_core(item_code);
