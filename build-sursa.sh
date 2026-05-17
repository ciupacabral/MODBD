#!/usr/bin/env bash
# =============================================================================
# build-sursa.sh — Consolideaza toate scripturile SQL/PL-SQL intr-un fisier text
# academic pentru livrabilul "_Sursa.txt" (cerinta 4 din baremul oficial).
#
# Output: docs/analiza/output/NUME_ECHIPA_Oprinoiu_Octavian_Sursa.txt
#
# Structura output-ului:
#   1. Header academic (cerinte Oracle, parole, note despre paths)
#   2. Ghid creare PDB-uri
#   3. Sectiuni clar marcate cu "RULEAZA CA: <USER> in PDB-ul <NAME>"
#   4. Codul SQL/PL-SQL inline pentru fiecare sectiune
#
# Re-generare: ./build-sursa.sh (idempotent)
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
OUTPUT="$REPO_ROOT/docs/analiza/output/NUME_ECHIPA_Oprinoiu_Octavian_Sursa.txt"
SQL_BASE="$REPO_ROOT/modbd/oracle"

mkdir -p "$(dirname "$OUTPUT")"

# Header helper (sectiune mare cu separator)
section_major() {
  local n="$1" title="$2"
  cat <<EOF >> "$OUTPUT"


-- =============================================================================
-- SECTIUNEA $n: $title
-- =============================================================================
EOF
}

# Connect helper (RULEAZA CA marker + CONNECT optional)
runs_as() {
  local user="$1" pdb="$2" desc="$3"
  cat <<EOF >> "$OUTPUT"

-- ============================================================================
-- RULEAZA CA: $user IN PDB-UL "$pdb"
-- $desc
--
-- In sqlplus, foloseste statement-ul CONNECT (sau /nolog + CONNECT) sau
-- conecteaza-te manual prin GUI (SQL Developer / DBeaver) cu credentialele
-- corespunzatoare. CONNECT-ul de mai jos arata parolele si serviciile noastre
-- (adapteaza-le pentru mediul tau).
-- ============================================================================
CONNECT $user/$([ "$user" = "sys" ] && echo "ModbdSecret123" || echo "oracle")@//localhost:1521/$pdb$([ "$user" = "sys" ] && echo " as sysdba")
EOF
}

# Sub-section header (script individual)
sub_section() {
  local title="$1"
  cat <<EOF >> "$OUTPUT"


-- ----------------------------------------------------------------------------
-- $title
-- ----------------------------------------------------------------------------
EOF
}

# ----- Start fresh -----
cat > "$OUTPUT" <<'EOF'
-- =============================================================================
-- MODBD - Bază de Date Distribuită B2B fashion (RO/CZ/SK)
-- Cod consolidat SQL/PL-SQL pentru livrabilul "_Sursa.txt"
-- =============================================================================
-- Proiect:  Metode de Optimizare si Distribuire in Baze de Date (MODBD)
-- Materie:  FMI Universitatea Bucuresti, anul universitar 2025-2026
-- Autor:    Octavian Oprinoiu
-- Echipa:   <<NUME_ECHIPA>>
-- Data:     2026-05-17
-- =============================================================================
--
-- CONTINUT
--   Sectiunea 1: Creare 3 PDB-uri (DISTRIBUTIE, CATALOG, VANZARI) - SYSDBA
--   Sectiunea 2: Utilizatori app + role + grant-uri - SYSDBA
--   Sectiunea 3: Director CSV (pentru external tables) - SYSDBA
--   Sectiunea 4: DDL + Load PDB DISTRIBUTIE - SGBD_DISTRIBUTIE
--   Sectiunea 5: DDL + Load PDB CATALOG (fragmentare verticala BEA) - SGBD_CATALOG
--   Sectiunea 6: DDL + Load PDB VANZARI (fragmente orizontale RO/EXT) - SGBD_VANZARI
--   Sectiunea 7: View-uri de transparenta + triggere INSTEAD OF - SGBD_VANZARI
--   Sectiunea 8: Materialized View LOGs pe master tables - SYSDBA
--   Sectiunea 9: DB links + 7 MV-uri replicate + 4 FK cross-PDB - SGBD_VANZARI
--   Sectiunea 10: Job DBMS_SCHEDULER (refresh @ 60s) - SGBD_VANZARI
--   Sectiunea 11: Trigger agregat coerenta sume doc/linii - SGBD_VANZARI
--   Sectiunea 12: Indecsi + DBMS_STATS - SGBD_VANZARI
--   Sectiunea 13: Cerere SQL complexa + EXPLAIN PLAN (RBO/CBO/DRIVING_SITE)
--   Sectiunea 14: Suite teste end-to-end de validare
--
-- =============================================================================
-- PRE-CERINTE
-- =============================================================================
--   1. Oracle Database 19c (Enterprise sau XE) sau 21c XE.
--   2. Un CDB (Container Database) cu cel putin 3 PDB-uri user disponibile
--      (XE accepta exact 3 user PDBs in afara de PDB$SEED).
--   3. Acces ca SYS cu privilegiu SYSDBA in CDB$ROOT.
--   4. Directorul cu cele 15 fisiere CSV anonimizate (vezi lista mai jos)
--      accesibil pe sistemul de fisiere unde ruleaza Oracle.
--
-- PAROLE FOLOSITE IN ACEST FISIER
--   SYS / SYSTEM:                   ModbdSecret123
--   SGBD_DISTRIBUTIE / SGBD_CATALOG / SGBD_VANZARI: oracle
--   (Daca le schimbi, adapteaza statement-urile CONNECT din fiecare sectiune.)
--
-- PATH-URI ORACLE (de adaptat pentru installul tau)
--   - File paths pentru datafile-urile PDB-urilor: in Sectiunea 1 sunt setate
--     conform XE (/opt/oracle/oradata/XE/...). Pentru Enterprise sau alta
--     locatie, modifica FILE_NAME_CONVERT.
--   - Directorul CSV: in Sectiunea 3 e setat la '/csv'. Modifica calea cu
--     locatia fisierelor CSV de pe serverul tau.
--
-- CELE 15 FISIERE CSV ASTEPTATE IN CSV_DIR
--   CLIENTI.csv, CONTACTE.csv, ZONE.csv, AGENTI.csv,
--   ZONE_AGENTI.csv, INTERVALE_PLATA.csv, ZONE_INTERVALE_PLATA.csv,
--   INTERVALE_PLATA_ZILE.csv, BRANDS.csv, ITEMS_CATEGORY.csv, ITEMS_TYPE.csv,
--   ITEMS_SEASONS.csv, ITEMS.csv, DOCS_HEADERS.csv, DOCS_LINES.csv
--
-- MOD DE RULARE
--   In sqlplus (recomandat): @/cale/catre/fisier (CONNECT-urile schimba
--                            automat utilizatorul intre sectiuni).
--   In SQL Developer / DBeaver: ruleaza fiecare sectiune SEPARAT, conectat
--                               manual la PDB-ul/userul indicat in header.
--
-- =============================================================================
-- IDEMPOTENTA
-- =============================================================================
-- Acest script este idempotent: rularea de mai multe ori produce acelasi
-- rezultat fara erori, datorita strategiei:
--   - Sectiunea 1: PDB-urile se creeaza doar daca nu exista (verificare v$pdbs)
--   - Sectiunea 2: DROP USER ... CASCADE elimina toate obiectele din schema
--     (tabele, view-uri, MV-uri, DB links, triggere, joburi) inainte de
--     re-creare. Asta inseamna ca DDL-urile ulterioare ruleaza intotdeauna
--     pe o schema goala -> nu sunt necesare clauze DROP IF EXISTS in ele.
--
-- =============================================================================

SET SQLBLANKLINES ON
SET ECHO ON
SET SERVEROUTPUT ON
SET LINESIZE 200
WHENEVER SQLERROR CONTINUE
EOF

# ============================================================================
# Sectiunea 1: PDBs
# ============================================================================
section_major "1" "CREARE PDB-URI (DISTRIBUTIE, CATALOG, VANZARI)"
runs_as "sys" "XE" "Creeaza cele 3 PDB-uri user."
sub_section "Eliminare PDB default XEPDB1 + creare DISTRIBUTIE / CATALOG / VANZARI"
cat "$SQL_BASE/01_create_pdbs.sql" >> "$OUTPUT"

# ============================================================================
# Sectiunea 2: Users
# ============================================================================
section_major "2" "UTILIZATORI APP + ROLE sgbd_role + GRANT-URI"
runs_as "sys" "XE" "Creeaza tablespace USERS + utilizatori app in fiecare PDB."
sub_section "Pentru fiecare PDB: tablespace, drop user vechi (CASCADE), role, user nou"
cat "$SQL_BASE/02_create_users.sql" >> "$OUTPUT"

# ============================================================================
# Sectiunea 3: CSV directory
# ============================================================================
section_major "3" "DIRECTOR CSV (pentru external tables)"
runs_as "sys" "XE" "Creeaza directory object CSV_DIR + grant READ utilizatorilor app."
sub_section "Directory CSV_DIR creat in fiecare din cele 3 PDB-uri (calea '/csv' - adapteaza)"
cat "$SQL_BASE/03_csv_directory.sql" >> "$OUTPUT"

# ============================================================================
# Sectiunea 4: DISTRIBUTIE
# ============================================================================
section_major "4" "PDB DISTRIBUTIE - DDL + LOAD DATE (CRM/Comercial)"
runs_as "sgbd_distributie" "DISTRIBUTIE" "8 tabele master + 8 FK locale + load CSV-uri."

sub_section "DDL: ZONE, AGENTI, CLIENTI, CLIENTI_CONTACTE, INTERVALE_PLATA, INTERVALE_PLATA_ZILE, ZONE_AGENTI (M:N), ZONE_INTERVALE_PLATA (M:N)"
cat "$SQL_BASE/ddl/10_ddl_distributie.sql" >> "$OUTPUT"

sub_section "LOAD via external tables (52 randuri total in 8 tabele)"
cat "$SQL_BASE/ddl/11_load_distributie.sql" >> "$OUTPUT"

# ============================================================================
# Sectiunea 5: CATALOG
# ============================================================================
section_major "5" "PDB CATALOG - DDL + LOAD DATE (fragmentare verticala BEA pe MS_ITEMS)"
runs_as "sgbd_catalog" "CATALOG" "Lookup-uri + ITEMS_CORE/ITEMS_EXTRA (fragmente V) + V_ITEMS + triggere."

sub_section "DDL: BRANDS, ITEMS_CATEGORY, ITEMS_TYPE, ITEMS_SEASONS, ITEMS_CORE, ITEMS_EXTRA + V_ITEMS + 3 triggere INSTEAD OF"
cat "$SQL_BASE/ddl/12_ddl_catalog.sql" >> "$OUTPUT"

sub_section "LOAD: 4 lookup-uri + ITEMS split in CORE (7 col)/EXTRA (7 col) - 6.550 randuri total"
cat "$SQL_BASE/ddl/13_load_catalog.sql" >> "$OUTPUT"

# ============================================================================
# Sectiunea 6: VANZARI - fragmente orizontale
# ============================================================================
section_major "6" "PDB VANZARI - DDL FRAGMENTE ORIZONTALE + LOAD"
runs_as "sgbd_vanzari" "VANZARI" "4 fragmente fizice: FISE_CLIENTI_RO/EXT + LINII_DOC_RO/EXT."

sub_section "DDL: FISE_CLIENTI_RO (moneda='RON') + FISE_CLIENTI_EXT (moneda<>'RON') + LINII_DOC_RO/EXT (fragm. derivata prin semijoin)"
cat "$SQL_BASE/ddl/14_ddl_vanzari_fragments.sql" >> "$OUTPUT"

sub_section "LOAD: FISE+LINII din CSV cu split pe Moneda (2.048 docs total, 5.598 linii total)"
cat "$SQL_BASE/ddl/15_load_vanzari.sql" >> "$OUTPUT"

# ============================================================================
# Sectiunea 7: Views transparenta
# ============================================================================
section_major "7" "VIEW-URI DE TRANSPARENTA (UNION ALL) + TRIGGERE INSTEAD OF"
runs_as "sgbd_vanzari" "VANZARI" "Transparenta orizontala + rutare DML cu INSTEAD OF triggere."

sub_section "V_FISE_CLIENTI = RO UNION ALL EXT + V_LINII_DOC = RO UNION ALL EXT + 5 triggere INSTEAD OF (INSERT/UPDATE/DELETE)"
cat "$SQL_BASE/ddl/16_views_transparenta.sql" >> "$OUTPUT"

# ============================================================================
# Sectiunea 8: MV logs (SYS)
# ============================================================================
section_major "8" "MV LOGS PE TABELELE MASTER (suport REFRESH FAST)"
runs_as "sys" "XE" "Creaza MV LOG pe 7 tabele master (DISTRIBUTIE + CATALOG)."

sub_section "MV LOGs WITH PRIMARY KEY, ROWID, SEQUENCE - permite REFRESH FAST incremental"
cat "$SQL_BASE/ddl/17_mv_logs.sql" >> "$OUTPUT"

# ============================================================================
# Sectiunea 9: DB links + MV-uri + FK cross-PDB
# ============================================================================
section_major "9" "DB LINKS + 7 MV-uri REPLICATE + 4 FK CROSS-PDB"
runs_as "sgbd_vanzari" "VANZARI" "Replicare + enforcement integritate cross-PDB."

sub_section "DB Links lnk_distributie + lnk_catalog (private la sgbd_vanzari)"
cat "$SQL_BASE/ddl/18_db_links.sql" >> "$OUTPUT"

sub_section "7 Materialized Views REFRESH FAST ON DEMAND + UK pentru a permite FK"
cat "$SQL_BASE/ddl/19_mvs_vanzari.sql" >> "$OUTPUT"

sub_section "FK cross-PDB: fise_clienti_ro/ext.cod_client -> mv_clienti, linii_doc_ro/ext.item_code -> mv_items_core"
cat "$SQL_BASE/ddl/20_cross_pdb_fks.sql" >> "$OUTPUT"

# ============================================================================
# Sectiunea 10: Job scheduler
# ============================================================================
section_major "10" "JOB DBMS_SCHEDULER (refresh MV-uri @ 60s)"
runs_as "sgbd_vanzari" "VANZARI" "Sincronizare programata MV-uri replicate."

sub_section "Job JOB_REFRESH_MVS apeleaza DBMS_MVIEW.REFRESH('MV_CLIENTI,...') FAST la fiecare 60 secunde"
cat "$SQL_BASE/ddl/21_refresh_job.sql" >> "$OUTPUT"

# ============================================================================
# Sectiunea 11: Trigger agregat
# ============================================================================
section_major "11" "TRIGGER AGREGAT - COERENTA SUMA DOC / SUMA LINII"
runs_as "sgbd_vanzari" "VANZARI" "Constrangere semantica cu agregat (curs cap. 3.4)."

sub_section "Trigger AFTER STATEMENT pe linii_doc_ro/ext - verifica amount_doc = SUM(linii) ± 0.01"
cat "$SQL_BASE/ddl/22_trigger_agregat.sql" >> "$OUTPUT"

# ============================================================================
# Sectiunea 12: Indecsi + statistici
# ============================================================================
section_major "12" "INDECSI PE FACT TABLES + DBMS_STATS"
runs_as "sgbd_vanzari" "VANZARI" "Suport pentru optimizarea cererii complexe."

sub_section "8 indecsi pe fise_clienti_ro/ext + linii_doc_ro/ext (coloanele cele mai filtrate/joined)"
cat "$SQL_BASE/ddl/23_indexes_stats.sql" >> "$OUTPUT"

# ============================================================================
# Sectiunea 13: Cerere complexa
# ============================================================================
section_major "13" "CERERE SQL COMPLEXA + EXPLAIN PLAN COMPARATIV"
runs_as "sgbd_vanzari" "VANZARI" "Top 10 agenti 2024 pe zona + categorie + 3 planuri de executie."

sub_section "Query touch-uieste toate 3 PDB-uri prin DB link (zone_agenti, agenti) + MV-uri locale + view-uri de transparenta. EXPLAIN PLAN cu RBO, CBO default, CBO + DRIVING_SITE."
cat "$SQL_BASE/ddl/30_query_complex.sql" >> "$OUTPUT"

# ============================================================================
# Sectiunea 14: Validare end-to-end
# ============================================================================
section_major "14" "TESTE END-TO-END DE VALIDARE"
runs_as "sgbd_vanzari" "VANZARI" "5 teste care confirma functionarea completa."

sub_section "Test 1: counts globale | Test 2: V_FISE = RO + EXT | Test 3: INSTEAD OF trigger ruteaza pe moneda | Test 4: FK cross-PDB respinge clienti inexistenti | Test 5: MV refresh manual propaga delta"
cat "$SQL_BASE/ddl/40_validare_end_to_end.sql" >> "$OUTPUT"

# ============================================================================
# Final
# ============================================================================
cat <<'EOF' >> "$OUTPUT"


-- =============================================================================
-- SFARSIT - Daca toate cele 14 sectiuni s-au rulat fara erori, baza de date
-- distribuita MODBD este complet functionala.
--
-- Rezultate asteptate dupa rulare:
--   * 3 PDB-uri OPEN (DISTRIBUTIE, CATALOG, VANZARI)
--   * 3 utilizatori app (SGBD_DISTRIBUTIE, SGBD_CATALOG, SGBD_VANZARI)
--   * Volume in tabele:
--       DISTRIBUTIE: 52 randuri in 8 tabele (CRM/Comercial)
--       CATALOG:     6.550 randuri in 6 tabele (catalog produse)
--       VANZARI:     2.048 documente + 5.518 linii in 4 fragmente fizice
--                    + 3.373 randuri in 7 MV-uri replicate
--   * Teste finale 1-5: toate trebuie sa afiseze PASS / valori asteptate
-- =============================================================================
EXIT
EOF

# --- Statistici ---
lines=$(wc -l < "$OUTPUT")
size_kb=$(($(wc -c < "$OUTPUT") / 1024))
echo "Generat: $OUTPUT"
echo "  Linii:  $lines"
echo "  Marime: ${size_kb} KB"
