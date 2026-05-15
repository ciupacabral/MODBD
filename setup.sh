#!/usr/bin/env bash
# =============================================================================
# setup.sh — Replicare automata a BD distribuite MODBD intr-un container Docker.
#
# Utilizare:
#   ./setup.sh              # setup complet (fresh install)
#   ./setup.sh --clean      # sterge containerul existent + setup complet
#   ./setup.sh --resume     # ruleaza doar pasii de schema (container deja ready)
#   ./setup.sh --validate   # ruleaza doar testele end-to-end
#   ./setup.sh --stop       # opreste containerul (date persistente)
#   ./setup.sh --start      # porneste containerul oprit
#
# Pre-cerinte: Docker Desktop instalat + cca 4 GB RAM alocate.
# Durata setup complet: 5-10 minute (in functie de viteza de pull a imaginii).
# =============================================================================

set -euo pipefail

# --- Config ---
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
CSV_HOST_DIR="$REPO_ROOT/modbd"
CONTAINER="oracle-modbd"
IMAGE="gvenzl/oracle-xe:21-slim-faststart"
SYS_PASS="ModbdSecret123"
APP_PASS="oracle"
ORACLE_VOLUME="oracle-modbd-data"

# --- Culori pentru output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# --- Pre-checks ---
require_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    err "Docker nu este instalat. Instaleaza Docker Desktop si re-incearca."
    exit 1
  fi
  if ! docker info >/dev/null 2>&1; then
    err "Docker daemon nu ruleaza. Porneste Docker Desktop."
    exit 1
  fi
}

container_exists() {
  docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER}\$"
}

container_running() {
  docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}\$"
}

# Check if DB is ready, isolating from pipefail (docker logs may SIGPIPE on early grep exit)
db_is_ready() {
  local logs
  logs=$(docker logs "$CONTAINER" 2>&1) || return 1
  grep -q "DATABASE IS READY TO USE" <<< "$logs"
}

# --- Actions ---
action_clean() {
  log "Cleanup: sterg containerul si volumul existente..."
  docker rm -f "$CONTAINER" 2>/dev/null || true
  docker volume rm "$ORACLE_VOLUME" 2>/dev/null || true
  ok "Cleanup complet."
}

action_create_container() {
  log "Pull imagine Oracle XE 21c (poate dura cateva minute la prima rulare)..."
  docker pull "$IMAGE"

  log "Creez containerul ${CONTAINER}..."
  docker run -d \
    --name "$CONTAINER" \
    --platform linux/amd64 \
    -p 1521:1521 \
    -e ORACLE_PASSWORD="$SYS_PASS" \
    -v "$ORACLE_VOLUME":/opt/oracle/oradata \
    -v "$CSV_HOST_DIR":/csv:ro \
    "$IMAGE"

  ok "Container creat. Astept ca BD-ul sa fie gata..."
  log "Initializarea la rece poate dura 10-20 minute (creare datafiles + PDB seed)."
  local attempts=0
  local max_attempts=240  # 20 minute maxim (init la rece e lent)
  until db_is_ready; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge "$max_attempts" ]; then
      err "Timeout asteptand Oracle dupa $((max_attempts * 5)) secunde."
      err "Verifica: docker logs $CONTAINER"
      err "Daca BD-ul e doar mai lent, poti relua cu: ./setup.sh --resume"
      exit 1
    fi
    sleep 5
    if [ $((attempts % 12)) -eq 0 ]; then
      log "  ... inca astept ($((attempts * 5)) secunde / max $((max_attempts * 5)))"
    fi
  done
  ok "BD-ul Oracle e gata."
}

action_start() {
  if ! container_exists; then
    err "Containerul ${CONTAINER} nu exista. Ruleaza ./setup.sh pentru a-l crea."
    exit 1
  fi
  if container_running; then
    ok "Containerul ${CONTAINER} ruleaza deja."
    return
  fi
  log "Pornesc containerul ${CONTAINER}..."
  docker start "$CONTAINER"
  log "Astept BD-ul sa fie gata..."
  local attempts=0
  until docker exec "$CONTAINER" healthcheck.sh 2>/dev/null; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 60 ]; then
      err "Timeout. Verifica: docker logs $CONTAINER"
      exit 1
    fi
    sleep 5
  done
  ok "Container pornit, BD gata."
}

action_stop() {
  if container_running; then
    log "Opresc containerul ${CONTAINER}..."
    docker stop "$CONTAINER"
    ok "Container oprit (datele sunt persistente in volumul ${ORACLE_VOLUME})."
  else
    log "Containerul ${CONTAINER} nu rula."
  fi
}

# --- SQL helpers ---
run_sql() {
  # $1 = connect string (ex: sys/PASS@//localhost:1521/XE as sysdba)
  # $2 = path to SQL file (inside container, ex: /csv/oracle/01_create_pdbs.sql)
  # SET SQLBLANKLINES ON: permite linii blank in interiorul statement-urilor SQL
  #   (necesar pentru CREATE VIEW cu UNION ALL formatat cu blank lines).
  # WHENEVER SQLERROR EXIT: opreste sqlplus la prima eroare ORA-* si propaga exit code.
  docker exec -i "$CONTAINER" bash -c "echo -e 'SET SQLBLANKLINES ON\nWHENEVER SQLERROR EXIT SQL.SQLCODE\n@${2}\nEXIT' | sqlplus -L -S '${1}'"
}

run_sys_sysdba() {
  run_sql "sys/${SYS_PASS}@//localhost:1521/XE as sysdba" "$1"
}

run_sys_pdb() {
  # ruleaza ca SYS cu posibilitatea de ALTER SESSION SET CONTAINER
  run_sql "sys/${SYS_PASS}@//localhost:1521/XE as sysdba" "$1"
}

run_app() {
  # $1 = user, $2 = PDB, $3 = script path
  run_sql "$1/${APP_PASS}@//localhost:1521/$2" "$3"
}

# --- Setup pipeline ---
action_setup_schema() {
  log "[1/17] Creez cele 3 PDB-uri (DISTRIBUTIE, CATALOG, VANZARI)..."
  run_sys_sysdba /csv/oracle/01_create_pdbs.sql
  ok "PDB-uri create."

  log "[2/17] Creez tablespace-uri + utilizatori app per PDB..."
  run_sys_sysdba /csv/oracle/02_create_users.sql
  ok "Utilizatori creati."

  log "[3/17] Configurez CSV_DIR + grant READ in fiecare PDB..."
  run_sys_sysdba /csv/oracle/03_csv_directory.sql
  ok "CSV directory configurat."

  log "[4/17] DDL DISTRIBUTIE (8 tabele + 8 FK)..."
  run_app sgbd_distributie DISTRIBUTIE /csv/oracle/ddl/10_ddl_distributie.sql
  ok "DDL DISTRIBUTIE."

  log "[5/17] Load date DISTRIBUTIE (52 randuri)..."
  run_app sgbd_distributie DISTRIBUTIE /csv/oracle/ddl/11_load_distributie.sql
  ok "Date DISTRIBUTIE incarcate."

  log "[6/17] DDL CATALOG (6 tabele + ITEMS_CORE/ITEMS_EXTRA + V_ITEMS + triggere)..."
  run_app sgbd_catalog CATALOG /csv/oracle/ddl/12_ddl_catalog.sql
  ok "DDL CATALOG."

  log "[7/17] Load date CATALOG (6.550 randuri, split CORE/EXTRA pe ITEMS)..."
  run_app sgbd_catalog CATALOG /csv/oracle/ddl/13_load_catalog.sql
  ok "Date CATALOG incarcate."

  log "[8/17] DDL VANZARI (fragmente orizontale: FISE_CLIENTI_RO/EXT + LINII_DOC_RO/EXT)..."
  run_app sgbd_vanzari VANZARI /csv/oracle/ddl/14_ddl_vanzari_fragments.sql
  ok "DDL VANZARI."

  log "[9/17] Load date VANZARI cu split pe Moneda (2.048 docs + 5.598 linii)..."
  run_app sgbd_vanzari VANZARI /csv/oracle/ddl/15_load_vanzari.sql
  ok "Date VANZARI incarcate."

  log "[10/17] View-uri UNION ALL + 5 triggere INSTEAD OF pentru transparenta..."
  run_app sgbd_vanzari VANZARI /csv/oracle/ddl/16_views_transparenta.sql
  ok "View-uri transparenta create."

  log "[11/17] MV logs pe tabelele master (DISTRIBUTIE + CATALOG) — ca SYS..."
  run_sys_sysdba /csv/oracle/ddl/17_mv_logs.sql
  ok "MV logs create."

  log "[12/17] DB links VANZARI -> DISTRIBUTIE + CATALOG..."
  run_app sgbd_vanzari VANZARI /csv/oracle/ddl/18_db_links.sql
  ok "DB links create."

  log "[13/17] 7 Materialized Views replicate in VANZARI..."
  run_app sgbd_vanzari VANZARI /csv/oracle/ddl/19_mvs_vanzari.sql
  ok "MV-uri replicate create."

  log "[14/17] 4 FK cross-PDB locale (catre MV-urile replicate)..."
  run_app sgbd_vanzari VANZARI /csv/oracle/ddl/20_cross_pdb_fks.sql
  ok "FK-uri cross-PDB activate."

  log "[15/17] Job DBMS_SCHEDULER pentru refresh MV @ 60s..."
  run_app sgbd_vanzari VANZARI /csv/oracle/ddl/21_refresh_job.sql
  ok "Job refresh activ."

  log "[16/17] Trigger agregat pentru coerenta sum_doc vs sum_linii..."
  run_app sgbd_vanzari VANZARI /csv/oracle/ddl/22_trigger_agregat.sql
  ok "Trigger agregat creat."

  log "[17/17] 8 indecsi pe fact tables + DBMS_STATS gathered..."
  run_app sgbd_vanzari VANZARI /csv/oracle/ddl/23_indexes_stats.sql
  ok "Indecsi si statistici create."
}

action_validate() {
  log "Rulez testele end-to-end..."
  run_app sgbd_vanzari VANZARI /csv/oracle/ddl/40_validare_end_to_end.sql
  ok "Validare completa."
}

action_query() {
  log "Rulez cererea complexa (top 10 agenti 2024) + EXPLAIN PLAN..."
  run_app sgbd_vanzari VANZARI /csv/oracle/ddl/30_query_complex.sql
  ok "Query rulat."
}

# --- Main ---
main() {
  require_docker

  case "${1:-}" in
    --clean)
      action_clean
      action_create_container
      action_setup_schema
      action_validate
      echo ""
      ok "Setup complet cu cleanup. BD-ul distribuit MODBD ruleaza pe localhost:1521."
      ;;
    --resume)
      if ! container_running; then
        err "Containerul nu ruleaza. Foloseste: ./setup.sh --start"
        exit 1
      fi
      if ! db_is_ready; then
        err "BD-ul Oracle nu pare gata in containerul existent."
        err "Verifica: docker logs $CONTAINER"
        exit 1
      fi
      action_setup_schema
      action_validate
      ;;
    --validate)
      if ! container_running; then
        err "Containerul nu ruleaza. Foloseste: ./setup.sh --start"
        exit 1
      fi
      action_validate
      ;;
    --query)
      if ! container_running; then
        err "Containerul nu ruleaza. Foloseste: ./setup.sh --start"
        exit 1
      fi
      action_query
      ;;
    --start)
      action_start
      ;;
    --stop)
      action_stop
      ;;
    --help|-h)
      head -16 "$0" | tail -14
      ;;
    "")
      if container_exists; then
        warn "Containerul ${CONTAINER} exista deja."
        warn "Pentru a sterge si re-crea: ./setup.sh --clean"
        warn "Pentru a porni containerul existent: ./setup.sh --start"
        warn "Pentru validare: ./setup.sh --validate"
        exit 1
      fi
      action_create_container
      action_setup_schema
      action_validate
      echo ""
      ok "Setup complet."
      echo ""
      echo "Conectare la PDB-uri:"
      echo "  DISTRIBUTIE: sqlplus sgbd_distributie/oracle@//localhost:1521/DISTRIBUTIE"
      echo "  CATALOG:     sqlplus sgbd_catalog/oracle@//localhost:1521/CATALOG"
      echo "  VANZARI:     sqlplus sgbd_vanzari/oracle@//localhost:1521/VANZARI"
      echo "  SYS:         sqlplus sys/${SYS_PASS}@//localhost:1521/XE as sysdba"
      ;;
    *)
      err "Argument necunoscut: $1"
      head -16 "$0" | tail -14
      exit 1
      ;;
  esac
}

main "$@"
