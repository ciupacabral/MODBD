-- =============================================================================
-- 16_views_transparenta.sql
-- View-uri UNION ALL pentru transparenta orizontala + INSTEAD OF triggers care
-- ruteaza DML catre fragmentul corespunzator (RO vs EXT) bazat pe moneda.
-- =============================================================================

CREATE OR REPLACE VIEW v_fise_clienti AS
SELECT * FROM fise_clienti_ro
UNION ALL
SELECT * FROM fise_clienti_ext;

CREATE OR REPLACE VIEW v_linii_doc AS
SELECT * FROM linii_doc_ro
UNION ALL
SELECT * FROM linii_doc_ext;

-- ===== INSTEAD OF triggers pe V_FISE_CLIENTI =====

CREATE OR REPLACE TRIGGER trg_v_fise_ins
INSTEAD OF INSERT ON v_fise_clienti
FOR EACH ROW
BEGIN
  IF :NEW.moneda = 'RON' THEN
    INSERT INTO fise_clienti_ro
      VALUES (:NEW.id, :NEW.nr_document, :NEW.nr_doc_initial, :NEW.tip_doc, :NEW.doc_type_xrp,
              :NEW.data_doc_efectiva, :NEW.data_scad, :NEW.semn, :NEW.moneda,
              :NEW.amount_doc, :NEW.amount_doc_ron, :NEW.plata_prin,
              :NEW.cod_client, :NEW.denumire_client, :NEW.clasa_client);
  ELSE
    INSERT INTO fise_clienti_ext
      VALUES (:NEW.id, :NEW.nr_document, :NEW.nr_doc_initial, :NEW.tip_doc, :NEW.doc_type_xrp,
              :NEW.data_doc_efectiva, :NEW.data_scad, :NEW.semn, :NEW.moneda,
              :NEW.amount_doc, :NEW.amount_doc_ron, :NEW.plata_prin,
              :NEW.cod_client, :NEW.denumire_client, :NEW.clasa_client);
  END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_v_fise_upd
INSTEAD OF UPDATE ON v_fise_clienti
FOR EACH ROW
BEGIN
  -- Mutare cross-fragment daca moneda se schimba din RON <-> non-RON
  IF :OLD.moneda = 'RON' AND :NEW.moneda <> 'RON' THEN
    DELETE FROM fise_clienti_ro WHERE id = :OLD.id;
    INSERT INTO fise_clienti_ext
      VALUES (:NEW.id, :NEW.nr_document, :NEW.nr_doc_initial, :NEW.tip_doc, :NEW.doc_type_xrp,
              :NEW.data_doc_efectiva, :NEW.data_scad, :NEW.semn, :NEW.moneda,
              :NEW.amount_doc, :NEW.amount_doc_ron, :NEW.plata_prin,
              :NEW.cod_client, :NEW.denumire_client, :NEW.clasa_client);
  ELSIF :OLD.moneda <> 'RON' AND :NEW.moneda = 'RON' THEN
    DELETE FROM fise_clienti_ext WHERE id = :OLD.id;
    INSERT INTO fise_clienti_ro
      VALUES (:NEW.id, :NEW.nr_document, :NEW.nr_doc_initial, :NEW.tip_doc, :NEW.doc_type_xrp,
              :NEW.data_doc_efectiva, :NEW.data_scad, :NEW.semn, :NEW.moneda,
              :NEW.amount_doc, :NEW.amount_doc_ron, :NEW.plata_prin,
              :NEW.cod_client, :NEW.denumire_client, :NEW.clasa_client);
  ELSIF :OLD.moneda = 'RON' THEN
    UPDATE fise_clienti_ro SET
      nr_document = :NEW.nr_document, nr_doc_initial = :NEW.nr_doc_initial,
      tip_doc = :NEW.tip_doc, doc_type_xrp = :NEW.doc_type_xrp,
      data_doc_efectiva = :NEW.data_doc_efectiva, data_scad = :NEW.data_scad,
      semn = :NEW.semn, moneda = :NEW.moneda,
      amount_doc = :NEW.amount_doc, amount_doc_ron = :NEW.amount_doc_ron,
      plata_prin = :NEW.plata_prin, cod_client = :NEW.cod_client,
      denumire_client = :NEW.denumire_client, clasa_client = :NEW.clasa_client
    WHERE id = :OLD.id;
  ELSE
    UPDATE fise_clienti_ext SET
      nr_document = :NEW.nr_document, nr_doc_initial = :NEW.nr_doc_initial,
      tip_doc = :NEW.tip_doc, doc_type_xrp = :NEW.doc_type_xrp,
      data_doc_efectiva = :NEW.data_doc_efectiva, data_scad = :NEW.data_scad,
      semn = :NEW.semn, moneda = :NEW.moneda,
      amount_doc = :NEW.amount_doc, amount_doc_ron = :NEW.amount_doc_ron,
      plata_prin = :NEW.plata_prin, cod_client = :NEW.cod_client,
      denumire_client = :NEW.denumire_client, clasa_client = :NEW.clasa_client
    WHERE id = :OLD.id;
  END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_v_fise_del
INSTEAD OF DELETE ON v_fise_clienti
FOR EACH ROW
BEGIN
  DELETE FROM fise_clienti_ro  WHERE id = :OLD.id;
  DELETE FROM fise_clienti_ext WHERE id = :OLD.id;
END;
/

-- ===== INSTEAD OF triggers pe V_LINII_DOC =====
-- Liniile se ruteaza dupa fragmentul de fise corespondent

CREATE OR REPLACE TRIGGER trg_v_lin_ins
INSTEAD OF INSERT ON v_linii_doc
FOR EACH ROW
DECLARE
  v_in_ro NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_in_ro FROM fise_clienti_ro
    WHERE nr_document = :NEW.nr_document AND doc_type_xrp = :NEW.doc_type_xrp;
  IF v_in_ro > 0 THEN
    INSERT INTO linii_doc_ro
      VALUES (:NEW.id, :NEW.doc_type_xrp, :NEW.nr_document, :NEW.item_code, :NEW.item_qty,
              :NEW.xrp_doc_valoare_fara_tva, :NEW.xrp_doc_tva, :NEW.xrp_doc_procent_tva,
              :NEW.xrp_doc_valoare_totala, :NEW.xrp_linie_is_with_vat,
              :NEW.xrp_linie_valoare_fara_tva, :NEW.xrp_linie_tva, :NEW.xrp_linie_proc_tva);
  ELSE
    INSERT INTO linii_doc_ext
      VALUES (:NEW.id, :NEW.doc_type_xrp, :NEW.nr_document, :NEW.item_code, :NEW.item_qty,
              :NEW.xrp_doc_valoare_fara_tva, :NEW.xrp_doc_tva, :NEW.xrp_doc_procent_tva,
              :NEW.xrp_doc_valoare_totala, :NEW.xrp_linie_is_with_vat,
              :NEW.xrp_linie_valoare_fara_tva, :NEW.xrp_linie_tva, :NEW.xrp_linie_proc_tva);
  END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_v_lin_del
INSTEAD OF DELETE ON v_linii_doc
FOR EACH ROW
BEGIN
  DELETE FROM linii_doc_ro  WHERE id = :OLD.id;
  DELETE FROM linii_doc_ext WHERE id = :OLD.id;
END;
/
