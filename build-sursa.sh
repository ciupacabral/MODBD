#!/usr/bin/env bash
# =============================================================================
# build-sursa.sh — Consolideaza toate scripturile SQL/PLSQL intr-un singur fisier
# pentru livrabilul oficial "_Sursa.txt" (cerinta din baremul proiectului).
#
# Output: docs/analiza/output/NUME_ECHIPA_Oprinoiu_Octavian_Sursa.txt
#
# Format: comentarii sectiune cu separatori vizuali + statement-uri CONNECT
# pentru a comuta intre PDB-uri/utilizatori. Poate fi rulat ca-atare:
#
#   docker cp output/NUME_ECHIPA_Oprinoiu_Octavian_Sursa.txt \
#     oracle-modbd:/tmp/sursa.sql
#   docker exec -it oracle-modbd sqlplus /nolog @/tmp/sursa.sql
#
# Pre-cerinta: container oracle-modbd PORNIT + BD ready, fara cele 3 PDB-uri
# (foloseste ./setup.sh --clean inainte pentru a porni de la zero).
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
OUTPUT="$REPO_ROOT/docs/analiza/output/NUME_ECHIPA_Oprinoiu_Octavian_Sursa.txt"
SQL_BASE="$REPO_ROOT/modbd/oracle"

mkdir -p "$(dirname "$OUTPUT")"

# --- Helper pentru append cu header ---
section_header() {
  local title="$1"
  cat <<EOF >> "$OUTPUT"


-- ============================================================================
-- $title
-- ============================================================================
EOF
}

# --- Start fresh ---
cat > "$OUTPUT" <<'EOF'
-- =============================================================================
-- MODBD — Sursa consolidata pentru Baza de Date Distribuita
-- =============================================================================
-- Proiect:  Metode de Optimizare si Distribuire in Baze de Date (MODBD)
-- Materie:  FMI Universitatea Bucuresti, an universitar 2025-2026
-- Autor:    Octavian Oprinoiu
-- Echipa:   <<NUME_ECHIPA>>
--
-- Acest fisier contine in ordine corecta TOATE scripturile SQL si PL/SQL
-- necesare pentru a recrea baza de date distribuita de la zero, inclusiv:
--   - Cele 3 PDB-uri Oracle (DISTRIBUTIE, CATALOG, VANZARI)
--   - Utilizatori aplicativi + role-uri + grant-uri
--   - 18 tabele master + fragmente + 7 materialized views
--   - View-uri de transparenta + triggere INSTEAD OF
--   - Database links cross-PDB
--   - Constrangeri de integritate locale + globale
--   - Job DBMS_SCHEDULER pentru refresh @ 60s
--   - Indecsi + statistici pentru optimizare
--   - Cerere SQL complexa + EXPLAIN PLAN
--   - Suite de teste end-to-end de validare
--
-- Modul de rulare:
--   1. Asigura-te ca rulezi pe un container Docker fresh oracle-modbd
--      (./setup.sh --clean produce starea ceruta).
--   2. Copiaza acest fisier in container:
--        docker cp <<NUME_ECHIPA>>_Oprinoiu_Octavian_Sursa.txt \
--          oracle-modbd:/tmp/sursa.sql
--   3. Ruleaza ca SYSDBA (statement-urile CONNECT din interior schimba apoi
--      utilizatorul/PDB-ul automat):
--        docker exec -it oracle-modbd sqlplus /nolog @/tmp/sursa.sql
--   4. Validarea finala se executa automat la sfarsit (testele 1-5).
--
-- Parole:
--   SYS / SYSTEM:                 ModbdSecret123
--   SGBD_DISTRIBUTIE/CATALOG/VANZARI: oracle
-- =============================================================================

SET SQLBLANKLINES ON
SET ECHO ON
SET SERVEROUTPUT ON
SET LINESIZE 200
WHENEVER SQLERROR CONTINUE
EOF

# --- 1. Bootstrap CDB (SYS) ---
section_header "PASUL 1: CONECTARE SYSDBA + CREARE PDB-uri"
cat <<'EOF' >> "$OUTPUT"
CONNECT sys/ModbdSecret123@//localhost:1521/XE as sysdba
EOF

section_header "01_create_pdbs.sql — Creeaza 3 PDB-uri (DISTRIBUTIE, CATALOG, VANZARI)"
cat "$SQL_BASE/01_create_pdbs.sql" >> "$OUTPUT"

section_header "02_create_users.sql — Tablespace + utilizatori app + role sgbd_role"
cat "$SQL_BASE/02_create_users.sql" >> "$OUTPUT"

section_header "03_csv_directory.sql — Directory CSV_DIR + grant READ in fiecare PDB"
cat "$SQL_BASE/03_csv_directory.sql" >> "$OUTPUT"

# --- 2. DISTRIBUTIE schema ---
section_header "PASUL 2: CONECTARE LA PDB DISTRIBUTIE ca SGBD_DISTRIBUTIE"
cat <<'EOF' >> "$OUTPUT"
CONNECT sgbd_distributie/oracle@//localhost:1521/DISTRIBUTIE
EOF

section_header "10_ddl_distributie.sql — 8 tabele master + 8 FK locale"
cat "$SQL_BASE/ddl/10_ddl_distributie.sql" >> "$OUTPUT"

section_header "11_load_distributie.sql — Load CSV via external tables (52 randuri)"
cat "$SQL_BASE/ddl/11_load_distributie.sql" >> "$OUTPUT"

# --- 3. CATALOG schema ---
section_header "PASUL 3: CONECTARE LA PDB CATALOG ca SGBD_CATALOG"
cat <<'EOF' >> "$OUTPUT"
CONNECT sgbd_catalog/oracle@//localhost:1521/CATALOG
EOF

section_header "12_ddl_catalog.sql — Lookup-uri + ITEMS_CORE/EXTRA + V_ITEMS + 3 triggere INSTEAD OF"
cat "$SQL_BASE/ddl/12_ddl_catalog.sql" >> "$OUTPUT"

section_header "13_load_catalog.sql — Load lookup-uri + split CORE/EXTRA pe ITEMS (6.550 randuri)"
cat "$SQL_BASE/ddl/13_load_catalog.sql" >> "$OUTPUT"

# --- 4. VANZARI schema (partea I — fragmente + load + transparenta) ---
section_header "PASUL 4: CONECTARE LA PDB VANZARI ca SGBD_VANZARI"
cat <<'EOF' >> "$OUTPUT"
CONNECT sgbd_vanzari/oracle@//localhost:1521/VANZARI
EOF

section_header "14_ddl_vanzari_fragments.sql — Fragmente orizontale: FISE_RO/EXT + LINII_RO/EXT"
cat "$SQL_BASE/ddl/14_ddl_vanzari_fragments.sql" >> "$OUTPUT"

section_header "15_load_vanzari.sql — Load FISE + LINII cu split pe Moneda (2.048 docs, 5.598 linii)"
cat "$SQL_BASE/ddl/15_load_vanzari.sql" >> "$OUTPUT"

section_header "16_views_transparenta.sql — View-uri UNION ALL + 5 triggere INSTEAD OF"
cat "$SQL_BASE/ddl/16_views_transparenta.sql" >> "$OUTPUT"

# --- 5. MV Logs pe master (SYS, alternand PDB-uri) ---
section_header "PASUL 5: CONECTARE SYSDBA pentru MV LOGs pe master tables"
cat <<'EOF' >> "$OUTPUT"
CONNECT sys/ModbdSecret123@//localhost:1521/XE as sysdba
EOF

section_header "17_mv_logs.sql — MV LOGs pe tabelele master din DISTRIBUTIE + CATALOG"
cat "$SQL_BASE/ddl/17_mv_logs.sql" >> "$OUTPUT"

# --- 6. VANZARI (partea II — DB links + MV-uri + FK cross-PDB + job + trigger + indecsi) ---
section_header "PASUL 6: REVENIRE LA PDB VANZARI pentru replicare + constrangeri"
cat <<'EOF' >> "$OUTPUT"
CONNECT sgbd_vanzari/oracle@//localhost:1521/VANZARI
EOF

section_header "18_db_links.sql — DB links VANZARI -> DISTRIBUTIE + CATALOG"
cat "$SQL_BASE/ddl/18_db_links.sql" >> "$OUTPUT"

section_header "19_mvs_vanzari.sql — 7 Materialized Views replicate (REFRESH FAST ON DEMAND)"
cat "$SQL_BASE/ddl/19_mvs_vanzari.sql" >> "$OUTPUT"

section_header "20_cross_pdb_fks.sql — 4 FK cross-PDB catre MV-uri replicate"
cat "$SQL_BASE/ddl/20_cross_pdb_fks.sql" >> "$OUTPUT"

section_header "21_refresh_job.sql — Job DBMS_SCHEDULER pentru refresh @ 60s"
cat "$SQL_BASE/ddl/21_refresh_job.sql" >> "$OUTPUT"

section_header "22_trigger_agregat.sql — Trigger agregat coerenta sum_doc vs sum_linii"
cat "$SQL_BASE/ddl/22_trigger_agregat.sql" >> "$OUTPUT"

section_header "23_indexes_stats.sql — 8 indecsi pe fact tables + DBMS_STATS"
cat "$SQL_BASE/ddl/23_indexes_stats.sql" >> "$OUTPUT"

# --- 7. Query + validare ---
section_header "PASUL 7: CERERE SQL COMPLEXA + EXPLAIN PLAN (RBO/CBO/DRIVING_SITE)"
cat "$SQL_BASE/ddl/30_query_complex.sql" >> "$OUTPUT"

section_header "PASUL 8: SUITA DE TESTE END-TO-END (5 teste)"
cat "$SQL_BASE/ddl/40_validare_end_to_end.sql" >> "$OUTPUT"

# --- Final ---
cat <<'EOF' >> "$OUTPUT"


-- ============================================================================
-- FINAL — Daca ai ajuns aici, rularea s-a incheiat cu succes.
-- ============================================================================
EXIT
EOF

# --- Statistici ---
lines=$(wc -l < "$OUTPUT")
size_kb=$(($(wc -c < "$OUTPUT") / 1024))
echo "✓ Generat: $OUTPUT"
echo "  Linii:   $lines"
echo "  Marime:  ${size_kb} KB"
