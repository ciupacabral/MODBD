-- =============================================================================
-- 16_views_transparenta.sql
-- View-uri UNION ALL pentru transparenta orizontala + INSTEAD OF triggers care
-- ruteaza DML catre fragmentul corespunzator (RO vs EXT) bazat pe moneda.
-- =============================================================================


-- ============================================================================
-- View V_FISE_CLIENTI: union all peste cele 2 fragmente orizontale (RO + EXT)
-- ============================================================================
CREATE OR REPLACE VIEW v_fise_clienti (
    id
  , nr_document
  , nr_doc_initial
  , tip_doc
  , doc_type_xrp
  , data_doc_efectiva
  , data_scad
  , semn
  , moneda
  , amount_doc
  , amount_doc_ron
  , plata_prin
  , cod_client
  , denumire_client
  , clasa_client
) AS
SELECT
    id
  , nr_document
  , nr_doc_initial
  , tip_doc
  , doc_type_xrp
  , data_doc_efectiva
  , data_scad
  , semn
  , moneda
  , amount_doc
  , amount_doc_ron
  , plata_prin
  , cod_client
  , denumire_client
  , clasa_client
FROM fise_clienti_ro

UNION ALL

SELECT
    id
  , nr_document
  , nr_doc_initial
  , tip_doc
  , doc_type_xrp
  , data_doc_efectiva
  , data_scad
  , semn
  , moneda
  , amount_doc
  , amount_doc_ron
  , plata_prin
  , cod_client
  , denumire_client
  , clasa_client
FROM fise_clienti_ext;


-- ============================================================================
-- View V_LINII_DOC: union all peste linii_doc_ro + linii_doc_ext (derivat)
-- ============================================================================
CREATE OR REPLACE VIEW v_linii_doc (
    id
  , doc_type_xrp
  , nr_document
  , item_code
  , item_qty
  , xrp_doc_valoare_fara_tva
  , xrp_doc_tva
  , xrp_doc_procent_tva
  , xrp_doc_valoare_totala
  , xrp_linie_is_with_vat
  , xrp_linie_valoare_fara_tva
  , xrp_linie_tva
  , xrp_linie_proc_tva
) AS
SELECT
    id
  , doc_type_xrp
  , nr_document
  , item_code
  , item_qty
  , xrp_doc_valoare_fara_tva
  , xrp_doc_tva
  , xrp_doc_procent_tva
  , xrp_doc_valoare_totala
  , xrp_linie_is_with_vat
  , xrp_linie_valoare_fara_tva
  , xrp_linie_tva
  , xrp_linie_proc_tva
FROM linii_doc_ro

UNION ALL

SELECT
    id
  , doc_type_xrp
  , nr_document
  , item_code
  , item_qty
  , xrp_doc_valoare_fara_tva
  , xrp_doc_tva
  , xrp_doc_procent_tva
  , xrp_doc_valoare_totala
  , xrp_linie_is_with_vat
  , xrp_linie_valoare_fara_tva
  , xrp_linie_tva
  , xrp_linie_proc_tva
FROM linii_doc_ext;


-- ============================================================================
-- Trigger INSTEAD OF INSERT pe V_FISE_CLIENTI
-- Routare dupa moneda: RON -> fise_clienti_ro, altfel -> fise_clienti_ext
-- ============================================================================
CREATE OR REPLACE TRIGGER trg_v_fise_ins
INSTEAD OF INSERT ON v_fise_clienti
FOR EACH ROW
BEGIN
    IF :NEW.moneda = 'RON' THEN
        INSERT INTO fise_clienti_ro (
            id
          , nr_document
          , nr_doc_initial
          , tip_doc
          , doc_type_xrp
          , data_doc_efectiva
          , data_scad
          , semn
          , moneda
          , amount_doc
          , amount_doc_ron
          , plata_prin
          , cod_client
          , denumire_client
          , clasa_client
        ) VALUES (
            :NEW.id
          , :NEW.nr_document
          , :NEW.nr_doc_initial
          , :NEW.tip_doc
          , :NEW.doc_type_xrp
          , :NEW.data_doc_efectiva
          , :NEW.data_scad
          , :NEW.semn
          , :NEW.moneda
          , :NEW.amount_doc
          , :NEW.amount_doc_ron
          , :NEW.plata_prin
          , :NEW.cod_client
          , :NEW.denumire_client
          , :NEW.clasa_client
        );
    ELSE
        INSERT INTO fise_clienti_ext (
            id
          , nr_document
          , nr_doc_initial
          , tip_doc
          , doc_type_xrp
          , data_doc_efectiva
          , data_scad
          , semn
          , moneda
          , amount_doc
          , amount_doc_ron
          , plata_prin
          , cod_client
          , denumire_client
          , clasa_client
        ) VALUES (
            :NEW.id
          , :NEW.nr_document
          , :NEW.nr_doc_initial
          , :NEW.tip_doc
          , :NEW.doc_type_xrp
          , :NEW.data_doc_efectiva
          , :NEW.data_scad
          , :NEW.semn
          , :NEW.moneda
          , :NEW.amount_doc
          , :NEW.amount_doc_ron
          , :NEW.plata_prin
          , :NEW.cod_client
          , :NEW.denumire_client
          , :NEW.clasa_client
        );
    END IF;
END;
/


-- ============================================================================
-- Trigger INSTEAD OF UPDATE pe V_FISE_CLIENTI
-- Patru cazuri:
--   1. RON -> non-RON  : delete din ro, insert in ext (mutare cross-fragment)
--   2. non-RON -> RON  : delete din ext, insert in ro (mutare cross-fragment)
--   3. ramane RON      : update in fragmentul ro
--   4. ramane non-RON  : update in fragmentul ext
-- ============================================================================
CREATE OR REPLACE TRIGGER trg_v_fise_upd
INSTEAD OF UPDATE ON v_fise_clienti
FOR EACH ROW
BEGIN
    -- Cazul 1: RON -> non-RON (mutare ro -> ext)
    IF :OLD.moneda = 'RON' AND :NEW.moneda <> 'RON' THEN

        DELETE FROM fise_clienti_ro
        WHERE id = :OLD.id;

        INSERT INTO fise_clienti_ext (
            id
          , nr_document
          , nr_doc_initial
          , tip_doc
          , doc_type_xrp
          , data_doc_efectiva
          , data_scad
          , semn
          , moneda
          , amount_doc
          , amount_doc_ron
          , plata_prin
          , cod_client
          , denumire_client
          , clasa_client
        ) VALUES (
            :NEW.id
          , :NEW.nr_document
          , :NEW.nr_doc_initial
          , :NEW.tip_doc
          , :NEW.doc_type_xrp
          , :NEW.data_doc_efectiva
          , :NEW.data_scad
          , :NEW.semn
          , :NEW.moneda
          , :NEW.amount_doc
          , :NEW.amount_doc_ron
          , :NEW.plata_prin
          , :NEW.cod_client
          , :NEW.denumire_client
          , :NEW.clasa_client
        );

    -- Cazul 2: non-RON -> RON (mutare ext -> ro)
    ELSIF :OLD.moneda <> 'RON' AND :NEW.moneda = 'RON' THEN

        DELETE FROM fise_clienti_ext
        WHERE id = :OLD.id;

        INSERT INTO fise_clienti_ro (
            id
          , nr_document
          , nr_doc_initial
          , tip_doc
          , doc_type_xrp
          , data_doc_efectiva
          , data_scad
          , semn
          , moneda
          , amount_doc
          , amount_doc_ron
          , plata_prin
          , cod_client
          , denumire_client
          , clasa_client
        ) VALUES (
            :NEW.id
          , :NEW.nr_document
          , :NEW.nr_doc_initial
          , :NEW.tip_doc
          , :NEW.doc_type_xrp
          , :NEW.data_doc_efectiva
          , :NEW.data_scad
          , :NEW.semn
          , :NEW.moneda
          , :NEW.amount_doc
          , :NEW.amount_doc_ron
          , :NEW.plata_prin
          , :NEW.cod_client
          , :NEW.denumire_client
          , :NEW.clasa_client
        );

    -- Cazul 3: ramane RON (update intra-fragment ro)
    ELSIF :OLD.moneda = 'RON' THEN

        UPDATE fise_clienti_ro
        SET
            nr_document       = :NEW.nr_document
          , nr_doc_initial    = :NEW.nr_doc_initial
          , tip_doc           = :NEW.tip_doc
          , doc_type_xrp      = :NEW.doc_type_xrp
          , data_doc_efectiva = :NEW.data_doc_efectiva
          , data_scad         = :NEW.data_scad
          , semn              = :NEW.semn
          , moneda            = :NEW.moneda
          , amount_doc        = :NEW.amount_doc
          , amount_doc_ron    = :NEW.amount_doc_ron
          , plata_prin        = :NEW.plata_prin
          , cod_client        = :NEW.cod_client
          , denumire_client   = :NEW.denumire_client
          , clasa_client      = :NEW.clasa_client
        WHERE id = :OLD.id;

    -- Cazul 4: ramane non-RON (update intra-fragment ext)
    ELSE

        UPDATE fise_clienti_ext
        SET
            nr_document       = :NEW.nr_document
          , nr_doc_initial    = :NEW.nr_doc_initial
          , tip_doc           = :NEW.tip_doc
          , doc_type_xrp      = :NEW.doc_type_xrp
          , data_doc_efectiva = :NEW.data_doc_efectiva
          , data_scad         = :NEW.data_scad
          , semn              = :NEW.semn
          , moneda            = :NEW.moneda
          , amount_doc        = :NEW.amount_doc
          , amount_doc_ron    = :NEW.amount_doc_ron
          , plata_prin        = :NEW.plata_prin
          , cod_client        = :NEW.cod_client
          , denumire_client   = :NEW.denumire_client
          , clasa_client      = :NEW.clasa_client
        WHERE id = :OLD.id;

    END IF;
END;
/


-- ============================================================================
-- Trigger INSTEAD OF DELETE pe V_FISE_CLIENTI
-- Sterge din ambele fragmente (oricum doar unul are randul cu id-ul cerut)
-- ============================================================================
CREATE OR REPLACE TRIGGER trg_v_fise_del
INSTEAD OF DELETE ON v_fise_clienti
FOR EACH ROW
BEGIN

    DELETE FROM fise_clienti_ro
    WHERE id = :OLD.id;

    DELETE FROM fise_clienti_ext
    WHERE id = :OLD.id;

END;
/


-- ============================================================================
-- Trigger INSTEAD OF INSERT pe V_LINII_DOC
-- Routare dupa fragmentul de FISE al documentului parinte:
--   - daca fise e in fise_clienti_ro -> linia merge in linii_doc_ro
--   - altfel -> linia merge in linii_doc_ext
-- ============================================================================
CREATE OR REPLACE TRIGGER trg_v_lin_ins
INSTEAD OF INSERT ON v_linii_doc
FOR EACH ROW
DECLARE
    v_in_ro NUMBER;
BEGIN

    SELECT COUNT(*) INTO v_in_ro
    FROM fise_clienti_ro
    WHERE nr_document  = :NEW.nr_document
      AND doc_type_xrp = :NEW.doc_type_xrp;

    IF v_in_ro > 0 THEN
        INSERT INTO linii_doc_ro (
            id
          , doc_type_xrp
          , nr_document
          , item_code
          , item_qty
          , xrp_doc_valoare_fara_tva
          , xrp_doc_tva
          , xrp_doc_procent_tva
          , xrp_doc_valoare_totala
          , xrp_linie_is_with_vat
          , xrp_linie_valoare_fara_tva
          , xrp_linie_tva
          , xrp_linie_proc_tva
        ) VALUES (
            :NEW.id
          , :NEW.doc_type_xrp
          , :NEW.nr_document
          , :NEW.item_code
          , :NEW.item_qty
          , :NEW.xrp_doc_valoare_fara_tva
          , :NEW.xrp_doc_tva
          , :NEW.xrp_doc_procent_tva
          , :NEW.xrp_doc_valoare_totala
          , :NEW.xrp_linie_is_with_vat
          , :NEW.xrp_linie_valoare_fara_tva
          , :NEW.xrp_linie_tva
          , :NEW.xrp_linie_proc_tva
        );
    ELSE
        INSERT INTO linii_doc_ext (
            id
          , doc_type_xrp
          , nr_document
          , item_code
          , item_qty
          , xrp_doc_valoare_fara_tva
          , xrp_doc_tva
          , xrp_doc_procent_tva
          , xrp_doc_valoare_totala
          , xrp_linie_is_with_vat
          , xrp_linie_valoare_fara_tva
          , xrp_linie_tva
          , xrp_linie_proc_tva
        ) VALUES (
            :NEW.id
          , :NEW.doc_type_xrp
          , :NEW.nr_document
          , :NEW.item_code
          , :NEW.item_qty
          , :NEW.xrp_doc_valoare_fara_tva
          , :NEW.xrp_doc_tva
          , :NEW.xrp_doc_procent_tva
          , :NEW.xrp_doc_valoare_totala
          , :NEW.xrp_linie_is_with_vat
          , :NEW.xrp_linie_valoare_fara_tva
          , :NEW.xrp_linie_tva
          , :NEW.xrp_linie_proc_tva
        );
    END IF;

END;
/


-- ============================================================================
-- Trigger INSTEAD OF DELETE pe V_LINII_DOC
-- ============================================================================
CREATE OR REPLACE TRIGGER trg_v_lin_del
INSTEAD OF DELETE ON v_linii_doc
FOR EACH ROW
BEGIN

    DELETE FROM linii_doc_ro
    WHERE id = :OLD.id;

    DELETE FROM linii_doc_ext
    WHERE id = :OLD.id;

END;
/
