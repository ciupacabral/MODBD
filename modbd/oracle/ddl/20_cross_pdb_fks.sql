-- =============================================================================
-- 20_cross_pdb_fks.sql
-- FK-uri locale catre MV-uri replicate, enforce constrangerile globale.
-- Aceste FK-uri se aplica DUPA ce MV-urile (Task 12) sunt populate.
--
-- NOTE: FK-urile pe cod_client (fise_clienti_ro/ext -> mv_clienti) au fost
-- adaugate in scriptul precedent (19_mvs_vanzari.sql).
-- Acest script trateaza FK-urile pe item_code (linii_doc_ro/ext -> mv_items_core).
--
-- Inainte de a putea aplica FK pe item_code, trebuie eliminate randurile orfane
-- din linii_doc unde item_code-ul nu exista in items_core (date inconsistente
-- in CSV-urile sursa).
-- =============================================================================


-- ============================================================================
-- Cleanup randurilor orfane (item_codes care nu exista in MV_ITEMS_CORE)
-- Acestea sunt date "murdare" din CSV-urile sursa, nu eroare de proces.
-- ============================================================================
DELETE FROM linii_doc_ro ldr
WHERE NOT EXISTS (
    SELECT 1
    FROM   mv_items_core mic
    WHERE  mic.item_code = ldr.item_code
);


DELETE FROM linii_doc_ext lde
WHERE NOT EXISTS (
    SELECT 1
    FROM   mv_items_core mic
    WHERE  mic.item_code = lde.item_code
);


COMMIT;


-- ============================================================================
-- FK-uri locale catre MV_CLIENTI (replicat in VANZARI, dar logic din DISTRIBUTIE)
-- ============================================================================
ALTER TABLE fise_clienti_ro
ADD CONSTRAINT fk_fise_ro_client
FOREIGN KEY (cod_client)
REFERENCES  mv_clienti (cod_client);


ALTER TABLE fise_clienti_ext
ADD CONSTRAINT fk_fise_ext_client
FOREIGN KEY (cod_client)
REFERENCES  mv_clienti (cod_client);


-- ============================================================================
-- FK-uri locale catre MV_ITEMS_CORE (replicat in VANZARI, dar logic din CATALOG)
-- ============================================================================
ALTER TABLE linii_doc_ro
ADD CONSTRAINT fk_lin_ro_item
FOREIGN KEY (item_code)
REFERENCES  mv_items_core (item_code);


ALTER TABLE linii_doc_ext
ADD CONSTRAINT fk_lin_ext_item
FOREIGN KEY (item_code)
REFERENCES  mv_items_core (item_code);
