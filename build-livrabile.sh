#!/usr/bin/env bash
# =============================================================================
# build-livrabile.sh - Genereaza 4 livrabile SQL/PL-SQL pentru proiectul MODBD.
#
# Fisierele produse in docs/analiza/output/:
#
#   1. Setup.sql            - One-time bootstrap: PDB-uri + useri + tabele + date.
#                             Pornind de la o BD complet noua, dupa rulare avem
#                             3 PDB-uri cu tabele populate (cu fragmentarea
#                             built-in). NU se rulează la examen.
#
#   2. Demo_Schema.sql      - Re-rulabil oricand: layerul de transparenta +
#                             replicare + constrangeri globale + optimizare.
#                             Include un bloc de cleanup la inceput, astfel
#                             ca rularea repetata regenereaza totul fara erori.
#                             Folosit pentru screenshots / demonstratii.
#
#   3. Demo_Queries.sql     - Query-uri demo: cerere complexa + EXPLAIN PLAN +
#                             5 teste end-to-end de validare. Folosit pentru
#                             a arata ca BD-ul functioneaza (counts, FK enforcement,
#                             MV sync, transparenta DML).
#
#   4. NUME_ECHIPA_Oprinoiu_Octavian_Sursa.txt  - Consolidare a celor 3 fisiere
#                             intr-un singur fisier conform cerintei oficiale a
#                             baremul. Acest fisier e pentru livrare profei.
#
# Re-generare: ./build-livrabile.sh (idempotent)
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$REPO_ROOT/docs/analiza/output"
SQL_BASE="$REPO_ROOT/modbd/oracle"

SETUP="$OUT_DIR/Setup.sql"
SCHEMA="$OUT_DIR/Demo_Schema.sql"
QUERIES="$OUT_DIR/Demo_Queries.sql"
SURSA="$OUT_DIR/NUME_ECHIPA_Oprinoiu_Octavian_Sursa.txt"

mkdir -p "$OUT_DIR"

# ----- Helper: header pentru CONNECT (sqlplus, in Setup.sql + Sursa.txt) -----
runs_as() {
  local out="$1" user="$2" pdb="$3" desc="$4"
  cat <<EOF >> "$out"


-- ============================================================================
-- RULEAZA CA: $user IN PDB-UL "$pdb"
-- $desc
-- ============================================================================
CONNECT $user/$([ "$user" = "sys" ] && echo "ModbdSecret123" || echo "oracle")@//localhost:1521/$pdb$([ "$user" = "sys" ] && echo " as sysdba")
EOF
}

# ----- Helper: banner pentru DBeaver (Demo_Schema.sql + Demo_Queries.sql) ----
# Acelasi info ca runs_as, dar fara statement-ul CONNECT (DBeaver nu il foloseste).
dbeaver_block() {
  local out="$1" bloc_n="$2" user="$3" pdb="$4" desc="$5"
  cat <<EOF >> "$out"


-- ############################################################################
-- ## BLOC $bloc_n: deschide in DBeaver o conexiune cu:
-- ##   User:  $user
-- ##   PDB:   $pdb
-- ##   Parola: $([ "$user" = "sys" ] && echo "ModbdSecret123 (role SYSDBA)" || echo "oracle (role Normal)")
-- ##
-- ## $desc
-- ## Apoi ruleaza tot codul din BLOC $bloc_n in acea sesiune.
-- ############################################################################
EOF
}

# ----- Helper: separator pentru subsectiuni -------------------------------
sub() {
  local out="$1" title="$2"
  cat <<EOF >> "$out"


-- ----------------------------------------------------------------------------
-- $title
-- ----------------------------------------------------------------------------
EOF
}

# ============================================================================
# 1. SETUP.SQL - bootstrap de la zero
# ============================================================================
cat > "$SETUP" <<'EOF'
-- =============================================================================
-- Setup.sql - Bootstrap initial pentru proiectul MODBD
-- =============================================================================
-- Pornind de la o BD complet noua (3 PDB-uri inca necreate), acest fisier:
--   1. Creeaza cele 3 PDB-uri (DISTRIBUTIE, CATALOG, VANZARI)
--   2. Creeaza utilizatori app + role + grant-uri
--   3. Creeaza directorul CSV pentru external tables
--   4. Creeaza tabelele pentru fiecare PDB (cu fragmentare built-in)
--   5. Populeaza tabelele cu date din cele 15 CSV-uri
--
-- Rezultat final: 3 PDB-uri cu tabele complete si populate.
-- Fragmentarea (verticala BEA pe ITEMS, orizontala primara pe FISE_CLIENTI,
-- orizontala derivata pe LINII_DOC) este aplicata direct in DDL-ul initial -
-- noi pornim cu o BD distribuita "din proiectare", nu re-organizam o BD
-- pre-existenta.
--
-- NU se ruleaza la demo / examen - acest fisier e doar pentru bootstrap.
-- Pentru re-rulare la demo, foloseste Demo_Schema.sql (re-creeaza doar
-- transparenta + replicarea + constrangerile globale, pe tabelele deja
-- populate de Setup.sql).
-- =============================================================================

SET SQLBLANKLINES ON
SET ECHO ON
SET SERVEROUTPUT ON
SET LINESIZE 200
WHENEVER SQLERROR CONTINUE
EOF

runs_as "$SETUP" "sys" "XE" "Bootstrap CDB - creare PDB-uri, useri, director CSV."
sub "$SETUP" "Pas 1.1: Creare 3 PDB-uri (idempotent prin verificare in v\$pdbs)"
cat "$SQL_BASE/01_create_pdbs.sql" >> "$SETUP"
sub "$SETUP" "Pas 1.2: Tablespace USERS + utilizatori app + role sgbd_role + grant-uri"
cat "$SQL_BASE/02_create_users.sql" >> "$SETUP"
sub "$SETUP" "Pas 1.3: Director CSV_DIR + grant READ"
cat "$SQL_BASE/03_csv_directory.sql" >> "$SETUP"

runs_as "$SETUP" "sgbd_distributie" "DISTRIBUTIE" "Schema CRM/Comercial: 8 tabele + load."
sub "$SETUP" "Pas 2.1: DDL - 8 tabele master + 8 FK locale"
cat "$SQL_BASE/ddl/10_ddl_distributie.sql" >> "$SETUP"
sub "$SETUP" "Pas 2.2: Load 52 randuri via external tables"
cat "$SQL_BASE/ddl/11_load_distributie.sql" >> "$SETUP"

runs_as "$SETUP" "sgbd_catalog" "CATALOG" "Catalog produse cu fragmentare verticala BEA."
sub "$SETUP" "Pas 3.1: DDL - 4 lookup + ITEMS_CORE/ITEMS_EXTRA (fragmente V)"
cat "$SQL_BASE/ddl/12_ddl_catalog.sql" >> "$SETUP"
sub "$SETUP" "Pas 3.2: Load 6.550 randuri (lookup-uri + ITEMS split CORE/EXTRA)"
cat "$SQL_BASE/ddl/13_load_catalog.sql" >> "$SETUP"

runs_as "$SETUP" "sgbd_vanzari" "VANZARI" "Fact tables cu fragmentare orizontala RO/EXT."
sub "$SETUP" "Pas 4.1: DDL - 4 fragmente fizice (FISE_CLIENTI_RO/EXT + LINII_DOC_RO/EXT)"
cat "$SQL_BASE/ddl/14_ddl_vanzari_fragments.sql" >> "$SETUP"
sub "$SETUP" "Pas 4.2: Load 2.048 docs + 5.518 linii cu split pe Moneda"
cat "$SQL_BASE/ddl/15_load_vanzari.sql" >> "$SETUP"

cat >> "$SETUP" <<'EOF'


-- =============================================================================
-- SFARSIT Setup.sql
-- Stare BD acum:
--   PDB DISTRIBUTIE: 52 randuri in 8 tabele
--   PDB CATALOG    : 6.550 randuri in 6 tabele (4 lookups + CORE + EXTRA)
--   PDB VANZARI    : 1.555 RO + 493 EXT documente (total 2.048)
--                    3.806 RO + 1.712 EXT linii (total 5.518)
--                    (au fost eliminati 80 orfani fara item_code valid la load)
--
-- Urmatorul pas: ruleaza Demo_Schema.sql pentru a adauga layerul de
-- transparenta + replicarea + constrangerile globale.
-- =============================================================================
EXIT
EOF

# ============================================================================
# 2. DEMO_SCHEMA.SQL - re-rulabil pentru demo (DBeaver-friendly)
# ============================================================================
cat > "$SCHEMA" <<'EOF'
-- =============================================================================
-- Demo_Schema.sql - Layerul de transparenta + replicare + optimizare
-- =============================================================================
-- IDEMPOTENT: poate fi rulat de oricate ori pe o BD care are deja tabelele
-- populate (vezi Setup.sql).
--
-- Mod de utilizare in DBeaver:
--   Fisierul e impartit in BLOC-uri vizibile. La inceputul fiecarui bloc
--   gasesti instructiunea "deschide in DBeaver o conexiune cu User/PDB X".
--   Comuta tab-ul / conexiunea conform indicatiei si ruleaza tot codul din
--   acel bloc (Ctrl+Alt+X / Cmd+Alt+X), apoi treci la blocul urmator.
--
-- Continut (in ordinea de executie):
--   BLOC 1: VANZARI - Cleanup (drop indexes, job, FK, MV-uri, DB links)
--   BLOC 2: SYS    - Cleanup + recreare MV LOGs pe master tables
--   BLOC 3: CATALOG - V_ITEMS + 3 triggere INSTEAD OF (transparenta verticala)
--   BLOC 4: VANZARI - V_FISE + V_LINII + 5 triggere (transparenta orizontala)
--                     + DB links + 7 MV-uri replicate + 4 FK cross-PDB
--                     + job DBMS_SCHEDULER + trigger agregat + 8 indecsi
--
-- Note tehnice:
--   - Idempotenta: cleanup-ul (BLOC 1 + 2) sterge tot ce nu suporta
--     CREATE OR REPLACE, astfel rularea repetata e safe.
--   - View-urile + triggerele folosesc CREATE OR REPLACE (idempotent).
--   - MV-urile + DB links + FK + indecsi + job NU au CREATE OR REPLACE,
--     de aceea trebuie drop-uite explicit inainte de re-creere.
-- =============================================================================
EOF

dbeaver_block "$SCHEMA" "1" "sgbd_vanzari" "VANZARI" "Cleanup VANZARI: drop indexes, job, FK cross-PDB, MV-uri, DB links."

cat >> "$SCHEMA" <<'EOF'

-- Drop 8 indecsi
BEGIN
    FOR i IN (
        SELECT 'idx_fise_ro_data'   AS n FROM dual UNION ALL
        SELECT 'idx_fise_ro_codcli'      FROM dual UNION ALL
        SELECT 'idx_fise_ro_tip'         FROM dual UNION ALL
        SELECT 'idx_fise_ext_data'       FROM dual UNION ALL
        SELECT 'idx_fise_ext_codcli'     FROM dual UNION ALL
        SELECT 'idx_fise_ext_tip'        FROM dual UNION ALL
        SELECT 'idx_lin_ro_item'         FROM dual UNION ALL
        SELECT 'idx_lin_ext_item'        FROM dual
    ) LOOP
        BEGIN
            EXECUTE IMMEDIATE 'DROP INDEX ' || i.n;
        EXCEPTION WHEN OTHERS THEN NULL;  -- index does not exist - OK
        END;
    END LOOP;
END;
/

-- Drop job DBMS_SCHEDULER
BEGIN
    DBMS_SCHEDULER.DROP_JOB(job_name => 'JOB_REFRESH_MVS', force => TRUE);
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

-- Drop 4 FK cross-PDB
BEGIN
    FOR c IN (
        SELECT 'fise_clienti_ro'  AS t, 'fk_fise_ro_client'  AS n FROM dual UNION ALL
        SELECT 'fise_clienti_ext'     , 'fk_fise_ext_client'      FROM dual UNION ALL
        SELECT 'linii_doc_ro'         , 'fk_lin_ro_item'          FROM dual UNION ALL
        SELECT 'linii_doc_ext'        , 'fk_lin_ext_item'         FROM dual
    ) LOOP
        BEGIN
            EXECUTE IMMEDIATE 'ALTER TABLE ' || c.t || ' DROP CONSTRAINT ' || c.n;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END LOOP;
END;
/

-- Drop 7 MV-uri replicate
BEGIN
    FOR m IN (
        SELECT 'mv_clienti' AS n FROM dual UNION ALL
        SELECT 'mv_zone'             FROM dual UNION ALL
        SELECT 'mv_items_core'       FROM dual UNION ALL
        SELECT 'mv_brands'           FROM dual UNION ALL
        SELECT 'mv_items_category'   FROM dual UNION ALL
        SELECT 'mv_items_type'       FROM dual UNION ALL
        SELECT 'mv_items_seasons'    FROM dual
    ) LOOP
        BEGIN
            EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW ' || m.n;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END LOOP;
END;
/

-- Drop 2 DB links
BEGIN EXECUTE IMMEDIATE 'DROP DATABASE LINK lnk_distributie'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP DATABASE LINK lnk_catalog';     EXCEPTION WHEN OTHERS THEN NULL; END;
/


EOF

# ----- BLOC 2: SYS pentru MV LOGs cleanup + recreare -----
dbeaver_block "$SCHEMA" "2" "sys" "XE" "Cleanup + recreare MV LOGs pe tabelele master (DISTRIBUTIE + CATALOG)."

cat >> "$SCHEMA" <<'EOF'

-- Drop MV LOGs (alternand PDB-uri prin ALTER SESSION SET CONTAINER)
ALTER SESSION SET CONTAINER      = DISTRIBUTIE;
ALTER SESSION SET CURRENT_SCHEMA = sgbd_distributie;

BEGIN EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW LOG ON clienti'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW LOG ON zone';    EXCEPTION WHEN OTHERS THEN NULL; END;
/

ALTER SESSION SET CONTAINER      = CATALOG;
ALTER SESSION SET CURRENT_SCHEMA = sgbd_catalog;

BEGIN EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW LOG ON items_core';     EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW LOG ON brands';         EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW LOG ON items_category'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW LOG ON items_type';     EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW LOG ON items_seasons';  EXCEPTION WHEN OTHERS THEN NULL; END;
/

EOF

# Re-creare MV LOGs (continut din 17_mv_logs.sql)
sub "$SCHEMA" "Re-creare MV LOGs (WITH PRIMARY KEY, ROWID, SEQUENCE pentru REFRESH FAST)"
cat "$SQL_BASE/ddl/17_mv_logs.sql" >> "$SCHEMA"

# ----- BLOC 3: CATALOG pentru V_ITEMS -----
dbeaver_block "$SCHEMA" "3" "sgbd_catalog" "CATALOG" "V_ITEMS + 3 INSTEAD OF triggere (transparenta verticala BEA)."
sub "$SCHEMA" "V_ITEMS = JOIN(ITEMS_CORE, ITEMS_EXTRA) + INSTEAD OF INSERT/UPDATE/DELETE"
cat "$SQL_BASE/ddl/16_v_items.sql" >> "$SCHEMA"

# ----- BLOC 4: VANZARI pentru tot restul -----
dbeaver_block "$SCHEMA" "4" "sgbd_vanzari" "VANZARI" "Transparenta orizontala + replicare + FK cross-PDB + job + agg trigger + indecsi."

sub "$SCHEMA" "V_FISE_CLIENTI = RO UNION ALL EXT + V_LINII_DOC = RO UNION ALL EXT + 5 triggere INSTEAD OF"
cat "$SQL_BASE/ddl/16_views_transparenta.sql" >> "$SCHEMA"

sub "$SCHEMA" "DB Links private lnk_distributie + lnk_catalog"
cat "$SQL_BASE/ddl/18_db_links.sql" >> "$SCHEMA"

sub "$SCHEMA" "7 MV-uri REFRESH FAST ON DEMAND + UK pentru a permite FK"
cat "$SQL_BASE/ddl/19_mvs_vanzari.sql" >> "$SCHEMA"

sub "$SCHEMA" "4 FK cross-PDB: fise->mv_clienti (2), linii->mv_items_core (2)"
cat "$SQL_BASE/ddl/20_cross_pdb_fks.sql" >> "$SCHEMA"

sub "$SCHEMA" "Job DBMS_SCHEDULER pentru refresh MV-uri la fiecare 60 secunde"
cat "$SQL_BASE/ddl/21_refresh_job.sql" >> "$SCHEMA"

sub "$SCHEMA" "Trigger AFTER STATEMENT - verificare coerenta sum_doc vs sum_linii"
cat "$SQL_BASE/ddl/22_trigger_agregat.sql" >> "$SCHEMA"

sub "$SCHEMA" "8 indecsi pe coloanele cele mai filtrate + DBMS_STATS gather"
cat "$SQL_BASE/ddl/23_indexes_stats.sql" >> "$SCHEMA"

cat >> "$SCHEMA" <<'EOF'


-- =============================================================================
-- SFARSIT Demo_Schema.sql
-- Componente create / re-create:
--   - V_ITEMS + 3 triggere INSTEAD OF (CATALOG)
--   - V_FISE_CLIENTI + V_LINII_DOC + 5 triggere INSTEAD OF (VANZARI)
--   - 7 MV LOGs pe master tables (DISTRIBUTIE + CATALOG)
--   - 2 DB links private (VANZARI)
--   - 7 Materialized Views replicate (VANZARI)
--   - 4 FK cross-PDB (VANZARI)
--   - 1 Job DBMS_SCHEDULER refresh @ 60s
--   - 2 triggere agregat coerenta sume (RO + EXT)
--   - 8 indecsi pe fact tables + statistici proaspete
--
-- Urmatorul pas: deschide Demo_Queries.sql (conectat ca sgbd_vanzari/VANZARI)
-- pentru a rula cererea complexa + 5 teste de validare.
-- =============================================================================
EOF

# ============================================================================
# 3. DEMO_QUERIES.SQL - verificari + demo interactiv (DBeaver-friendly)
# ============================================================================
cat > "$QUERIES" <<'EOF'
-- =============================================================================
-- Demo_Queries.sql - Query-uri demo pentru verificare si screenshots
-- =============================================================================
-- Contine:
--   - Cererea SQL complexa (top 10 agenti 2024 pe zona + categorie)
--   - 3 EXPLAIN PLAN comparativ (RBO / CBO default / CBO + DRIVING_SITE)
--   - 5 teste end-to-end automate (counts, transparenta, INSTEAD OF, FK, MV sync)
--
-- Mod de utilizare in DBeaver:
--   Toate query-urile ruleaza in PDB-ul VANZARI ca utilizator SGBD_VANZARI.
--   Deschide o sesiune cu aceasta conexiune, apoi ruleaza cate o
--   instructiune pe rand (Cmd+Enter pentru fiecare).
--
-- Pre-cerinte: Setup.sql + Demo_Schema.sql au rulat deja, BD e populata.
-- Note: testele 3 si 4 fac INSERT / UPDATE / DELETE cu ROLLBACK la final,
--       deci nu modifica datele.
-- =============================================================================
EOF

dbeaver_block "$QUERIES" "1" "sgbd_vanzari" "VANZARI" "Toate query-urile demo (1 cerere complexa + 5 teste de validare)."

sub "$QUERIES" "Cererea SQL complexa: top 10 agenti 2024, defalcat pe zona + categorie. Touch 3 PDB-uri."
cat "$SQL_BASE/ddl/30_query_complex.sql" >> "$QUERIES"

sub "$QUERIES" "Suita 5 teste end-to-end de validare"
cat "$SQL_BASE/ddl/40_validare_end_to_end.sql" >> "$QUERIES"

cat >> "$QUERIES" <<'EOF'


-- =============================================================================
-- SFARSIT Demo_Queries.sql
-- =============================================================================
EOF

# ============================================================================
# 4. NUME_ECHIPA_..._SURSA.TXT - livrabil oficial (sqlplus-friendly cu CONNECTs)
# ============================================================================
cat > "$SURSA" <<'EOF'
-- =============================================================================
-- MODBD - Cod consolidat SQL/PL-SQL pentru livrabilul "_Sursa.txt"
-- =============================================================================
-- Proiect:  Metode de Optimizare si Distribuire in Baze de Date (MODBD)
-- Materie:  FMI Universitatea Bucuresti, anul universitar 2025-2026
-- Autor:    Octavian Oprinoiu
-- Echipa:   <<NUME_ECHIPA>>
-- Data:     2026-05-17
-- =============================================================================
--
-- Acest fisier contine tot codul SQL/PL-SQL al proiectului in ordinea corecta
-- de executie, cu statement-uri CONNECT explicite pentru fiecare sectiune.
-- Rulabil in sqlplus prin: sqlplus /nolog @<filename>
--
-- Continut:
--   PARTEA 1 (~1700 linii): Bootstrap - PDB-uri + useri + tabele + date
--   PARTEA 2 (~1200 linii): Transparenta + replicare + constrangeri globale
--   PARTEA 3 (~400 linii):  Cerere complexa + EXPLAIN PLAN + 5 teste validare
--
-- Pre-cerinte:
--   Oracle Database 19c/21c (Enterprise sau XE), CDB cu >=3 PDB-uri user
--   disponibile, acces SYS cu SYSDBA in CDB$ROOT, cele 15 fisiere CSV
--   anonimizate accesibile in directorul indicat la CREATE DIRECTORY CSV_DIR.
--
-- Parole:
--   SYS / SYSTEM:                   ModbdSecret123
--   SGBD_DISTRIBUTIE/CATALOG/VANZARI: oracle
-- =============================================================================

SET SQLBLANKLINES ON
SET ECHO ON
SET SERVEROUTPUT ON
SET LINESIZE 200
WHENEVER SQLERROR CONTINUE


-- #############################################################################
-- ## PARTEA 1: SETUP - Bootstrap PDB-uri + useri + tabele + date
-- #############################################################################
EOF

# PARTEA 1: setup (CONNECTs incluse via runs_as)
runs_as "$SURSA" "sys" "XE" "Bootstrap CDB - creare PDB-uri, useri, director CSV."
sub "$SURSA" "Pas 1.1: Creare 3 PDB-uri (idempotent prin verificare in v\$pdbs)"
cat "$SQL_BASE/01_create_pdbs.sql" >> "$SURSA"
sub "$SURSA" "Pas 1.2: Tablespace USERS + utilizatori app + role sgbd_role + grant-uri"
cat "$SQL_BASE/02_create_users.sql" >> "$SURSA"
sub "$SURSA" "Pas 1.3: Director CSV_DIR + grant READ"
cat "$SQL_BASE/03_csv_directory.sql" >> "$SURSA"

runs_as "$SURSA" "sgbd_distributie" "DISTRIBUTIE" "Schema CRM/Comercial."
sub "$SURSA" "DDL DISTRIBUTIE - 8 tabele master + 8 FK locale"
cat "$SQL_BASE/ddl/10_ddl_distributie.sql" >> "$SURSA"
sub "$SURSA" "LOAD DISTRIBUTIE - 52 randuri via external tables"
cat "$SQL_BASE/ddl/11_load_distributie.sql" >> "$SURSA"

runs_as "$SURSA" "sgbd_catalog" "CATALOG" "Catalog produse cu fragmentare verticala BEA."
sub "$SURSA" "DDL CATALOG - 4 lookup + ITEMS_CORE/ITEMS_EXTRA"
cat "$SQL_BASE/ddl/12_ddl_catalog.sql" >> "$SURSA"
sub "$SURSA" "LOAD CATALOG - 6.550 randuri"
cat "$SQL_BASE/ddl/13_load_catalog.sql" >> "$SURSA"

runs_as "$SURSA" "sgbd_vanzari" "VANZARI" "Fact tables cu fragmentare orizontala RO/EXT."
sub "$SURSA" "DDL VANZARI - 4 fragmente fizice"
cat "$SQL_BASE/ddl/14_ddl_vanzari_fragments.sql" >> "$SURSA"
sub "$SURSA" "LOAD VANZARI - 2.048 docs + 5.518 linii split pe Moneda"
cat "$SQL_BASE/ddl/15_load_vanzari.sql" >> "$SURSA"

# PARTEA 2: transparenta + replicare + optimizare
cat >> "$SURSA" <<'EOF'


-- #############################################################################
-- ## PARTEA 2: DEMO_SCHEMA - Transparenta + replicare + constrangeri globale
-- #############################################################################
-- (Aceasta parte este idempotenta - poate fi rulata de mai multe ori daca
--  re-rulati Sursa.txt pe o BD pre-existenta.)
-- #############################################################################
EOF

runs_as "$SURSA" "sgbd_vanzari" "VANZARI" "Cleanup VANZARI: drop indexes, job, FK cross-PDB, MV-uri, DB links."
cat >> "$SURSA" <<'EOF'

-- Drop 8 indecsi
BEGIN
    FOR i IN (
        SELECT 'idx_fise_ro_data'   AS n FROM dual UNION ALL
        SELECT 'idx_fise_ro_codcli'      FROM dual UNION ALL
        SELECT 'idx_fise_ro_tip'         FROM dual UNION ALL
        SELECT 'idx_fise_ext_data'       FROM dual UNION ALL
        SELECT 'idx_fise_ext_codcli'     FROM dual UNION ALL
        SELECT 'idx_fise_ext_tip'        FROM dual UNION ALL
        SELECT 'idx_lin_ro_item'         FROM dual UNION ALL
        SELECT 'idx_lin_ext_item'        FROM dual
    ) LOOP
        BEGIN
            EXECUTE IMMEDIATE 'DROP INDEX ' || i.n;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END LOOP;
END;
/

-- Drop job DBMS_SCHEDULER
BEGIN
    DBMS_SCHEDULER.DROP_JOB(job_name => 'JOB_REFRESH_MVS', force => TRUE);
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

-- Drop 4 FK cross-PDB
BEGIN
    FOR c IN (
        SELECT 'fise_clienti_ro'  AS t, 'fk_fise_ro_client'  AS n FROM dual UNION ALL
        SELECT 'fise_clienti_ext'     , 'fk_fise_ext_client'      FROM dual UNION ALL
        SELECT 'linii_doc_ro'         , 'fk_lin_ro_item'          FROM dual UNION ALL
        SELECT 'linii_doc_ext'        , 'fk_lin_ext_item'         FROM dual
    ) LOOP
        BEGIN
            EXECUTE IMMEDIATE 'ALTER TABLE ' || c.t || ' DROP CONSTRAINT ' || c.n;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END LOOP;
END;
/

-- Drop 7 MV-uri replicate
BEGIN
    FOR m IN (
        SELECT 'mv_clienti' AS n FROM dual UNION ALL
        SELECT 'mv_zone'             FROM dual UNION ALL
        SELECT 'mv_items_core'       FROM dual UNION ALL
        SELECT 'mv_brands'           FROM dual UNION ALL
        SELECT 'mv_items_category'   FROM dual UNION ALL
        SELECT 'mv_items_type'       FROM dual UNION ALL
        SELECT 'mv_items_seasons'    FROM dual
    ) LOOP
        BEGIN
            EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW ' || m.n;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END LOOP;
END;
/

-- Drop 2 DB links
BEGIN EXECUTE IMMEDIATE 'DROP DATABASE LINK lnk_distributie'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP DATABASE LINK lnk_catalog';     EXCEPTION WHEN OTHERS THEN NULL; END;
/
EOF

runs_as "$SURSA" "sys" "XE" "Cleanup + recreare MV LOGs pe master tables (DISTRIBUTIE + CATALOG)."
cat >> "$SURSA" <<'EOF'

-- Drop MV LOGs (alternand PDB-uri prin ALTER SESSION)
ALTER SESSION SET CONTAINER      = DISTRIBUTIE;
ALTER SESSION SET CURRENT_SCHEMA = sgbd_distributie;
BEGIN EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW LOG ON clienti'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW LOG ON zone';    EXCEPTION WHEN OTHERS THEN NULL; END;
/

ALTER SESSION SET CONTAINER      = CATALOG;
ALTER SESSION SET CURRENT_SCHEMA = sgbd_catalog;
BEGIN EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW LOG ON items_core';     EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW LOG ON brands';         EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW LOG ON items_category'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW LOG ON items_type';     EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW LOG ON items_seasons';  EXCEPTION WHEN OTHERS THEN NULL; END;
/
EOF

sub "$SURSA" "Re-creare MV LOGs"
cat "$SQL_BASE/ddl/17_mv_logs.sql" >> "$SURSA"

runs_as "$SURSA" "sgbd_catalog" "CATALOG" "V_ITEMS + 3 INSTEAD OF triggere."
cat "$SQL_BASE/ddl/16_v_items.sql" >> "$SURSA"

runs_as "$SURSA" "sgbd_vanzari" "VANZARI" "Transparenta orizontala + replicare + FK cross-PDB + job + agg trigger + indecsi."
sub "$SURSA" "V_FISE + V_LINII + 5 INSTEAD OF triggere"
cat "$SQL_BASE/ddl/16_views_transparenta.sql" >> "$SURSA"
sub "$SURSA" "DB Links private"
cat "$SQL_BASE/ddl/18_db_links.sql" >> "$SURSA"
sub "$SURSA" "7 MV-uri REFRESH FAST"
cat "$SQL_BASE/ddl/19_mvs_vanzari.sql" >> "$SURSA"
sub "$SURSA" "4 FK cross-PDB"
cat "$SQL_BASE/ddl/20_cross_pdb_fks.sql" >> "$SURSA"
sub "$SURSA" "Job DBMS_SCHEDULER refresh @ 60s"
cat "$SQL_BASE/ddl/21_refresh_job.sql" >> "$SURSA"
sub "$SURSA" "Trigger agregat coerenta sume"
cat "$SQL_BASE/ddl/22_trigger_agregat.sql" >> "$SURSA"
sub "$SURSA" "8 indecsi + DBMS_STATS"
cat "$SQL_BASE/ddl/23_indexes_stats.sql" >> "$SURSA"

# PARTEA 3: query complex + validare
cat >> "$SURSA" <<'EOF'


-- #############################################################################
-- ## PARTEA 3: DEMO_QUERIES - Cerere complexa + 5 teste validare
-- #############################################################################
EOF

runs_as "$SURSA" "sgbd_vanzari" "VANZARI" "Cerere complexa + 5 teste validare."
sub "$SURSA" "Cererea complexa: top 10 agenti 2024 + 3 EXPLAIN PLAN"
cat "$SQL_BASE/ddl/30_query_complex.sql" >> "$SURSA"
sub "$SURSA" "Suite 5 teste end-to-end de validare"
cat "$SQL_BASE/ddl/40_validare_end_to_end.sql" >> "$SURSA"

cat >> "$SURSA" <<'EOF'


-- =============================================================================
-- SFARSIT Sursa.txt - vezi rezultate teste 1-5 mai sus
-- =============================================================================
EXIT
EOF

# ----- Stats -----
echo ""
echo "Fisiere generate in $OUT_DIR:"
for f in "$SETUP" "$SCHEMA" "$QUERIES" "$SURSA"; do
  printf "  %-52s %5d linii  %5d KB\n" \
    "$(basename "$f")" \
    "$(wc -l < "$f")" \
    "$(($(wc -c < "$f") / 1024))"
done
