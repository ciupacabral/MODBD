# MODBD BD Oracle distribuit — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implementează modulul 2 al proiectului MODBD — BD Oracle distribuită (3 PDB-uri DISTRIBUTIE/CATALOG/VANZARI) cu fragmentări orizontale/verticale/derivate, replicare prin MV-uri, transparență prin view-uri, sincronizare programată și optimizare query distribuit.

**Architecture:** 3 PDB-uri într-un CDB Oracle 21c XE rulând în Docker. Date încărcate prin external tables din CSV-urile mounted. Fragmentele fizice expuse prin view-uri UNION ALL (orizontal) și JOIN (vertical) cu trigger-e INSTEAD OF pentru DML transparent. Replicarea cross-PDB via MV-uri cu refresh la 60s prin DBMS_SCHEDULER. Constrângerile cross-PDB enforce-uite ca FK locale pe MV-uri replicate. Query complex demonstrează RBO/CBO/DRIVING_SITE prin EXPLAIN PLAN.

**Tech Stack:** Oracle Database 21c XE, SQL*Plus, DBMS_SCHEDULER, DBMS_MVIEW, External Tables, Docker Desktop, Mac M4 (Apple Silicon + Rosetta).

**Spec:** [`docs/superpowers/specs/2026-05-14-modbd-bd-oracle-design.md`](../specs/2026-05-14-modbd-bd-oracle-design.md)

---

## File Structure

```
/Users/octav/MODBD/
├── .gitignore                                        (new)
├── MODBD_HANDOFF.md                                  (existing)
├── docs/superpowers/
│   ├── specs/2026-05-14-modbd-bd-oracle-design.md   (existing)
│   └── plans/2026-05-14-modbd-implementation.md     (this file)
└── modbd/
    ├── *.csv  (15 fișiere, existente)
    └── oracle/
        ├── 01_create_pdbs.sql                       (existing, ran)
        ├── 02_create_users.sql                      (existing, ran)
        ├── 03_csv_directory.sql                     (Task 2)
        └── ddl/
            ├── 10_ddl_distributie.sql               (Task 3)
            ├── 11_load_distributie.sql              (Task 4)
            ├── 12_ddl_catalog.sql                   (Task 5)
            ├── 13_load_catalog.sql                  (Task 6)
            ├── 14_ddl_vanzari_fragments.sql         (Task 7)
            ├── 15_load_vanzari.sql                  (Task 8)
            ├── 16_views_transparenta.sql            (Task 9)
            ├── 17_mv_logs.sql                       (Task 10)
            ├── 18_db_links.sql                      (Task 11)
            ├── 19_mvs_vanzari.sql                   (Task 12)
            ├── 20_cross_pdb_fks.sql                 (Task 12)
            ├── 21_refresh_job.sql                   (Task 13)
            ├── 22_trigger_agregat.sql               (Task 14)
            ├── 23_indexes_stats.sql                 (Task 15)
            └── 30_query_complex.sql                 (Tasks 16-17)
```

**File responsibilities:**
- `01-02`: bootstrap CDB → 3 PDB-uri + role + utilizatori (deja rulat)
- `03`: directory object pentru external tables (CDB-level, granturi spre PDB-uri)
- `10-11`: DISTRIBUTIE schema + populare
- `12-13`: CATALOG schema + populare (cu split vertical ITEMS → CORE/EXTRA)
- `14-15`: VANZARI fragmente fizice + populare (cu split orizontal FISE/LINII per Moneda)
- `16`: View-uri de transparență (UNION ALL + JOIN) + INSTEAD OF triggers
- `17-18`: MV logs pe master + DB links din VANZARI
- `19-20`: MV-uri replicate + FK-uri cross-PDB locale
- `21`: DBMS_SCHEDULER pentru refresh 60s
- `22`: Trigger agregat pentru coerență sum-document
- `23`: Indecși + DBMS_STATS
- `30`: Query complex + EXPLAIN PLAN (RBO/CBO/DRIVING_SITE)

---

## Convenții folosite în toate task-urile

**Conectare ca SYS la CDB**:
```bash
docker exec -i oracle-modbd sqlplus -s sys/ModbdSecret123@localhost:1521/XE as sysdba
```

**Conectare ca user aplicativ la PDB** (`<pdb>` ∈ {distributie, catalog, vanzari}):
```bash
docker exec -i oracle-modbd sqlplus -s sgbd_<pdb>/oracle@localhost:1521/<PDB_UPPER>
```

**Rulare script SQL din host**:
```bash
docker exec -i oracle-modbd sqlplus -s <user>/<pass>@localhost:1521/<service> < /path/on/host/script.sql
```

**Verify counts after every population step**:
```sql
SELECT COUNT(*) FROM <table>;
```

**Commit message format**: `tip: descriere scurtă` (ex: `feat: DDL DISTRIBUTIE`, `data: load CATALOG`, `chore: indexes`)

---

## Task 1: Init git + commit existing work

**Files:**
- Create: `/Users/octav/MODBD/.gitignore`
- Modify: (git initialization in `/Users/octav/MODBD/`)

- [ ] **Step 1: Verify we're not already in a git repo**

Run:
```bash
cd /Users/octav/MODBD && git status 2>&1
```
Expected: `fatal: not a git repository (or any of the parent directories): .git`

- [ ] **Step 2: Init git repo**

Run:
```bash
cd /Users/octav/MODBD && git init
```
Expected output ends with: `Initialized empty Git repository in /Users/octav/MODBD/.git/`

- [ ] **Step 2b: Set LOCAL git identity (do NOT use --global)**

Override global config (work email) cu email personal, dar doar pentru acest repo:
```bash
cd /Users/octav/MODBD && \
  git config --local user.email "octavoprinoiu17@gmail.com" && \
  git config --local user.name "Octavian Oprinoiu"
```
Verify:
```bash
cd /Users/octav/MODBD && git config --local user.email && git config --local user.name
```
Expected: `octavoprinoiu17@gmail.com` and `Octavian Oprinoiu`.

⚠️ **IMPORTANT**: NU folosi `--global` și NU modifica `~/.gitconfig`. Doar `--local` în acest repo.

- [ ] **Step 3: Create .gitignore**

Write to `/Users/octav/MODBD/.gitignore`:
```
# macOS
.DS_Store
._.DS_Store

# Editor
.vscode/
.idea/

# Oracle / SQL tooling
*.log
*.bad
*.dsc

# Outputs de implementare temporare
/tmp/
scratch/
```

- [ ] **Step 4: Verify status shows untracked files**

Run:
```bash
cd /Users/octav/MODBD && git status --short
```
Expected: lists `.gitignore`, `MODBD_HANDOFF.md`, `Cerinte si barem proiect MODBD IF 2025-2026 (1).pdf`, `docs/`, `modbd/` as untracked (with `??`).

- [ ] **Step 5: Initial commit**

Run:
```bash
cd /Users/octav/MODBD && \
  git add .gitignore MODBD_HANDOFF.md "Cerinte si barem proiect MODBD IF 2025-2026 (1).pdf" docs/ modbd/oracle/ modbd/*.csv && \
  git commit -m "chore: initial commit (handoff, spec, plan, infra SQL, CSV data)"
```
Expected: `[main (root-commit) <hash>] chore: initial commit (...)` with summary of files.

---

## Task 2: External-table directory object

**Files:**
- Create: `modbd/oracle/03_csv_directory.sql`

- [ ] **Step 1: Write the verification (test)**

Save as `/tmp/test_csv_dir.sql`:
```sql
ALTER SESSION SET CONTAINER = DISTRIBUTIE;
SELECT COUNT(*) AS dirs FROM all_directories WHERE directory_name = 'CSV_DIR';
EXIT;
```

Run:
```bash
docker exec -i oracle-modbd sqlplus -s sys/ModbdSecret123@localhost:1521/XE as sysdba < /tmp/test_csv_dir.sql
```
Expected: `DIRS` returned as `0` (no directory exists yet).

- [ ] **Step 2: Write the DDL**

Create `/Users/octav/MODBD/modbd/oracle/03_csv_directory.sql`:
```sql
-- =============================================================================
-- 03_csv_directory.sql
-- Creeaza directory object CSV_DIR pointand la /csv (mount-ul Docker) in fiecare
-- PDB si acorda READ pe el utilizatorilor aplicativi.
-- =============================================================================

ALTER SESSION SET CONTAINER = DISTRIBUTIE;
CREATE OR REPLACE DIRECTORY csv_dir AS '/csv';
GRANT READ ON DIRECTORY csv_dir TO sgbd_distributie;

ALTER SESSION SET CONTAINER = CATALOG;
CREATE OR REPLACE DIRECTORY csv_dir AS '/csv';
GRANT READ ON DIRECTORY csv_dir TO sgbd_catalog;

ALTER SESSION SET CONTAINER = VANZARI;
CREATE OR REPLACE DIRECTORY csv_dir AS '/csv';
GRANT READ ON DIRECTORY csv_dir TO sgbd_vanzari;
```

- [ ] **Step 3: Run the script**

```bash
docker exec -i oracle-modbd sqlplus -s sys/ModbdSecret123@localhost:1521/XE as sysdba < /Users/octav/MODBD/modbd/oracle/03_csv_directory.sql
```
Expected: 3× `Session altered.`, 3× `Directory created.`, 3× `Grant succeeded.`

- [ ] **Step 4: Re-run the verification — should now succeed**

```bash
docker exec -i oracle-modbd sqlplus -s sys/ModbdSecret123@localhost:1521/XE as sysdba < /tmp/test_csv_dir.sql
```
Expected: `DIRS` returned as `1`.

- [ ] **Step 5: Verify CSV files are visible from inside the container**

```bash
docker exec oracle-modbd ls /csv/ | head -20
```
Expected: lists CSV-urile (`AGENTI.csv`, `BRANDS.csv`, etc.)

- [ ] **Step 6: Commit**

```bash
cd /Users/octav/MODBD && \
  git add modbd/oracle/03_csv_directory.sql && \
  git commit -m "feat: external-table directory CSV_DIR in all PDBs"
```

---

## Task 3: DDL DISTRIBUTIE (8 tabele + constrângeri locale)

**Files:**
- Create: `modbd/oracle/ddl/10_ddl_distributie.sql`

- [ ] **Step 1: Write the verification (test) — table count should be 0**

Save as `/tmp/test_distr_tables.sql`:
```sql
SELECT COUNT(*) AS n_tables FROM user_tables;
EXIT;
```

Run:
```bash
docker exec -i oracle-modbd sqlplus -s sgbd_distributie/oracle@localhost:1521/DISTRIBUTIE < /tmp/test_distr_tables.sql
```
Expected: `N_TABLES` = `0`.

- [ ] **Step 2: Write the DDL**

Create `/Users/octav/MODBD/modbd/oracle/ddl/10_ddl_distributie.sql`:
```sql
-- =============================================================================
-- 10_ddl_distributie.sql
-- Schema DISTRIBUTIE (sgbd_distributie): CRM/comercial.
-- 8 tabele: ZONE, AGENTI, CLIENTI, CLIENTI_CONTACTE, INTERVALE_PLATA,
--          INTERVALE_PLATA_ZILE, ZONE_AGENTI (M:N), ZONE_INTERVALE_PLATA (M:N).
-- =============================================================================

CREATE TABLE zone (
  id              NUMBER(19) PRIMARY KEY,
  cod_zona        VARCHAR2(40)  NOT NULL,
  den_zona        VARCHAR2(80)  NOT NULL,
  tip_zona        VARCHAR2(10)  NOT NULL,
  parent_zona_id  NUMBER(19),
  CONSTRAINT uk_zone_cod UNIQUE (cod_zona),
  CONSTRAINT fk_zone_parent FOREIGN KEY (parent_zona_id) REFERENCES zone(id)
);

CREATE TABLE agenti (
  id          NUMBER(19) PRIMARY KEY,
  cod_agent   VARCHAR2(20)  NOT NULL,
  nume_agent  VARCHAR2(100) NOT NULL,
  email       VARCHAR2(200),
  CONSTRAINT uk_agenti_cod UNIQUE (cod_agent)
);

CREATE TABLE clienti (
  id               NUMBER(19) PRIMARY KEY,
  cod_client       VARCHAR2(60)  NOT NULL,
  denumire_client  VARCHAR2(200) NOT NULL,
  tip_client       VARCHAR2(12)  NOT NULL,
  id_zona          NUMBER(19)    NOT NULL,
  start_date       DATE          NOT NULL,
  end_date         DATE,
  CONSTRAINT uk_clienti_cod UNIQUE (cod_client),
  CONSTRAINT fk_clienti_zona FOREIGN KEY (id_zona) REFERENCES zone(id),
  CONSTRAINT ck_clienti_dates CHECK (end_date IS NULL OR end_date > start_date)
);

CREATE TABLE clienti_contacte (
  cod_client    VARCHAR2(60)   PRIMARY KEY,
  email_client  VARCHAR2(1000),
  email_agent   VARCHAR2(1000),
  CONSTRAINT fk_contacte_client FOREIGN KEY (cod_client) REFERENCES clienti(cod_client)
);

CREATE TABLE intervale_plata (
  id            NUMBER(19) PRIMARY KEY,
  den_interval  VARCHAR2(60) NOT NULL,
  CONSTRAINT uk_intpl_den UNIQUE (den_interval)
);

CREATE TABLE intervale_plata_zile (
  id_interval  NUMBER(19)   NOT NULL,
  per_zile     VARCHAR2(40) NOT NULL,
  zile_start   NUMBER(10)   NOT NULL,
  zile_end     NUMBER(10),
  CONSTRAINT pk_intpl_zile PRIMARY KEY (id_interval, per_zile),
  CONSTRAINT fk_intpl_zile FOREIGN KEY (id_interval) REFERENCES intervale_plata(id)
);

CREATE TABLE zone_agenti (
  id          NUMBER(19) PRIMARY KEY,
  id_zona     NUMBER(19) NOT NULL,
  id_agent    NUMBER(19) NOT NULL,
  start_date  DATE       NOT NULL,
  end_date    DATE,
  CONSTRAINT fk_za_zona FOREIGN KEY (id_zona) REFERENCES zone(id),
  CONSTRAINT fk_za_agent FOREIGN KEY (id_agent) REFERENCES agenti(id),
  CONSTRAINT ck_za_dates CHECK (end_date IS NULL OR end_date > start_date)
);

CREATE TABLE zone_intervale_plata (
  id           NUMBER(19) PRIMARY KEY,
  id_zona      NUMBER(19) NOT NULL,
  id_interval  NUMBER(19) NOT NULL,
  start_date   DATE       NOT NULL,
  end_date     DATE,
  CONSTRAINT fk_zip_zona FOREIGN KEY (id_zona) REFERENCES zone(id),
  CONSTRAINT fk_zip_interval FOREIGN KEY (id_interval) REFERENCES intervale_plata(id),
  CONSTRAINT ck_zip_dates CHECK (end_date IS NULL OR end_date > start_date)
);
```

- [ ] **Step 3: Run the DDL**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_distributie/oracle@localhost:1521/DISTRIBUTIE < /Users/octav/MODBD/modbd/oracle/ddl/10_ddl_distributie.sql
```
Expected: 8× `Table created.`

- [ ] **Step 4: Re-run verification — should now show 8 tables**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_distributie/oracle@localhost:1521/DISTRIBUTIE < /tmp/test_distr_tables.sql
```
Expected: `N_TABLES` = `8`.

- [ ] **Step 5: Verify FK count**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_distributie/oracle@localhost:1521/DISTRIBUTIE <<'EOF'
SELECT COUNT(*) AS n_fks FROM user_constraints WHERE constraint_type='R';
EXIT
EOF
```
Expected: `N_FKS` = `7` (zone self-FK + 6 inter-table FKs: contacte→client, intpl_zile→intpl, 2× za, 2× zip).

- [ ] **Step 6: Commit**

```bash
cd /Users/octav/MODBD && \
  git add modbd/oracle/ddl/10_ddl_distributie.sql && \
  git commit -m "feat: DDL DISTRIBUTIE (8 tables + FK constraints)"
```

---

## Task 4: Load DISTRIBUTIE (external tables + INSERTs)

**Files:**
- Create: `modbd/oracle/ddl/11_load_distributie.sql`

- [ ] **Step 1: Write verification (test) — all tables empty**

Save as `/tmp/test_distr_counts.sql`:
```sql
SELECT 'zone' AS t, COUNT(*) AS n FROM zone
UNION ALL SELECT 'agenti', COUNT(*) FROM agenti
UNION ALL SELECT 'clienti', COUNT(*) FROM clienti
UNION ALL SELECT 'clienti_contacte', COUNT(*) FROM clienti_contacte
UNION ALL SELECT 'intervale_plata', COUNT(*) FROM intervale_plata
UNION ALL SELECT 'intervale_plata_zile', COUNT(*) FROM intervale_plata_zile
UNION ALL SELECT 'zone_agenti', COUNT(*) FROM zone_agenti
UNION ALL SELECT 'zone_intervale_plata', COUNT(*) FROM zone_intervale_plata;
EXIT
```

Run:
```bash
docker exec -i oracle-modbd sqlplus -s sgbd_distributie/oracle@localhost:1521/DISTRIBUTIE < /tmp/test_distr_counts.sql
```
Expected: all rows show `N` = `0`.

- [ ] **Step 2: Write load script with external tables**

Create `/Users/octav/MODBD/modbd/oracle/ddl/11_load_distributie.sql`:
```sql
-- =============================================================================
-- 11_load_distributie.sql
-- Incarca cele 8 CSV-uri ale schemei DISTRIBUTIE prin external tables.
-- CSV-urile au header (SKIP 1) + BOM UTF-8 (ignorat de CHARACTERSET UTF8).
-- 'NULL' (string) e tradus in valoare NULL prin NULLIF.
-- =============================================================================

-- Pattern generic pentru toate cele 8 tabele:
-- 1. Creeaza external table ext_<tabel> care mapeaza CSV-ul
-- 2. INSERT INTO <tabel> SELECT ... FROM ext_<tabel>
-- 3. DROP external table (cleanup)

-- ZONE
CREATE TABLE ext_zone (
  id NUMBER(19), cod_zona VARCHAR2(40), den_zona VARCHAR2(80),
  tip_zona VARCHAR2(10), parent_zona_id VARCHAR2(20)
)
ORGANIZATION EXTERNAL (
  TYPE ORACLE_LOADER DEFAULT DIRECTORY csv_dir
  ACCESS PARAMETERS (
    RECORDS DELIMITED BY NEWLINE CHARACTERSET UTF8 SKIP 1
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    MISSING FIELD VALUES ARE NULL
  )
  LOCATION ('ZONE.csv')
) REJECT LIMIT UNLIMITED;

INSERT INTO zone (id, cod_zona, den_zona, tip_zona, parent_zona_id)
SELECT id, cod_zona, den_zona, tip_zona,
       NULLIF(parent_zona_id, 'NULL')
FROM ext_zone;
DROP TABLE ext_zone;

-- AGENTI
CREATE TABLE ext_agenti (
  id NUMBER(19), cod_agent VARCHAR2(20), nume_agent VARCHAR2(100), email VARCHAR2(200)
)
ORGANIZATION EXTERNAL (
  TYPE ORACLE_LOADER DEFAULT DIRECTORY csv_dir
  ACCESS PARAMETERS (
    RECORDS DELIMITED BY NEWLINE CHARACTERSET UTF8 SKIP 1
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    MISSING FIELD VALUES ARE NULL
  )
  LOCATION ('AGENTI.csv')
) REJECT LIMIT UNLIMITED;

INSERT INTO agenti SELECT * FROM ext_agenti;
DROP TABLE ext_agenti;

-- CLIENTI
CREATE TABLE ext_clienti (
  id NUMBER(19), cod_client VARCHAR2(60), denumire_client VARCHAR2(200),
  tip_client VARCHAR2(12), id_zona NUMBER(19),
  start_date VARCHAR2(20), end_date VARCHAR2(20)
)
ORGANIZATION EXTERNAL (
  TYPE ORACLE_LOADER DEFAULT DIRECTORY csv_dir
  ACCESS PARAMETERS (
    RECORDS DELIMITED BY NEWLINE CHARACTERSET UTF8 SKIP 1
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    MISSING FIELD VALUES ARE NULL
  )
  LOCATION ('CLIENTI.csv')
) REJECT LIMIT UNLIMITED;

INSERT INTO clienti (id, cod_client, denumire_client, tip_client, id_zona, start_date, end_date)
SELECT id, cod_client, denumire_client, tip_client, id_zona,
       TO_DATE(start_date, 'YYYY-MM-DD'),
       CASE WHEN end_date='NULL' THEN NULL ELSE TO_DATE(end_date, 'YYYY-MM-DD') END
FROM ext_clienti;
DROP TABLE ext_clienti;

-- CLIENTI_CONTACTE
CREATE TABLE ext_contacte (
  cod_client VARCHAR2(60), email_client VARCHAR2(1000), email_agent VARCHAR2(1000)
)
ORGANIZATION EXTERNAL (
  TYPE ORACLE_LOADER DEFAULT DIRECTORY csv_dir
  ACCESS PARAMETERS (
    RECORDS DELIMITED BY NEWLINE CHARACTERSET UTF8 SKIP 1
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    MISSING FIELD VALUES ARE NULL
  )
  LOCATION ('CONTACTE.csv')
) REJECT LIMIT UNLIMITED;

INSERT INTO clienti_contacte SELECT * FROM ext_contacte;
DROP TABLE ext_contacte;

-- INTERVALE_PLATA
CREATE TABLE ext_intpl (
  id NUMBER(19), den_interval VARCHAR2(60)
)
ORGANIZATION EXTERNAL (
  TYPE ORACLE_LOADER DEFAULT DIRECTORY csv_dir
  ACCESS PARAMETERS (
    RECORDS DELIMITED BY NEWLINE CHARACTERSET UTF8 SKIP 1
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    MISSING FIELD VALUES ARE NULL
  )
  LOCATION ('INTERVALE_PLATA.csv')
) REJECT LIMIT UNLIMITED;

INSERT INTO intervale_plata SELECT * FROM ext_intpl;
DROP TABLE ext_intpl;

-- INTERVALE_PLATA_ZILE
CREATE TABLE ext_intpl_zile (
  id_interval NUMBER(19), per_zile VARCHAR2(40),
  zile_start NUMBER(10), zile_end VARCHAR2(10)
)
ORGANIZATION EXTERNAL (
  TYPE ORACLE_LOADER DEFAULT DIRECTORY csv_dir
  ACCESS PARAMETERS (
    RECORDS DELIMITED BY NEWLINE CHARACTERSET UTF8 SKIP 1
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    MISSING FIELD VALUES ARE NULL
  )
  LOCATION ('INTERVALE_PLATA_ZILE.csv')
) REJECT LIMIT UNLIMITED;

INSERT INTO intervale_plata_zile (id_interval, per_zile, zile_start, zile_end)
SELECT id_interval, per_zile, zile_start,
       CASE WHEN zile_end='NULL' THEN NULL ELSE TO_NUMBER(zile_end) END
FROM ext_intpl_zile;
DROP TABLE ext_intpl_zile;

-- ZONE_AGENTI
CREATE TABLE ext_za (
  id NUMBER(19), id_zona NUMBER(19), id_agent NUMBER(19),
  start_date VARCHAR2(20), end_date VARCHAR2(20)
)
ORGANIZATION EXTERNAL (
  TYPE ORACLE_LOADER DEFAULT DIRECTORY csv_dir
  ACCESS PARAMETERS (
    RECORDS DELIMITED BY NEWLINE CHARACTERSET UTF8 SKIP 1
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    MISSING FIELD VALUES ARE NULL
  )
  LOCATION ('ZONE_AGENTI.csv')
) REJECT LIMIT UNLIMITED;

INSERT INTO zone_agenti (id, id_zona, id_agent, start_date, end_date)
SELECT id, id_zona, id_agent,
       TO_DATE(start_date, 'YYYY-MM-DD'),
       CASE WHEN end_date='NULL' THEN NULL ELSE TO_DATE(end_date, 'YYYY-MM-DD') END
FROM ext_za;
DROP TABLE ext_za;

-- ZONE_INTERVALE_PLATA
CREATE TABLE ext_zip (
  id NUMBER(19), id_zona NUMBER(19), id_interval NUMBER(19),
  start_date VARCHAR2(20), end_date VARCHAR2(20)
)
ORGANIZATION EXTERNAL (
  TYPE ORACLE_LOADER DEFAULT DIRECTORY csv_dir
  ACCESS PARAMETERS (
    RECORDS DELIMITED BY NEWLINE CHARACTERSET UTF8 SKIP 1
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    MISSING FIELD VALUES ARE NULL
  )
  LOCATION ('ZONE_INTERVALE_PLATA.csv')
) REJECT LIMIT UNLIMITED;

INSERT INTO zone_intervale_plata (id, id_zona, id_interval, start_date, end_date)
SELECT id, id_zona, id_interval,
       TO_DATE(start_date, 'YYYY-MM-DD'),
       CASE WHEN end_date='NULL' THEN NULL ELSE TO_DATE(end_date, 'YYYY-MM-DD') END
FROM ext_zip;
DROP TABLE ext_zip;

COMMIT;
```

- [ ] **Step 3: Run the load**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_distributie/oracle@localhost:1521/DISTRIBUTIE < /Users/octav/MODBD/modbd/oracle/ddl/11_load_distributie.sql
```
Expected: many `Table created.` / `8 rows created.` / `Table dropped.` messages, final `Commit complete.`

- [ ] **Step 4: Re-run verification — counts should match expected**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_distributie/oracle@localhost:1521/DISTRIBUTIE < /tmp/test_distr_counts.sql
```
Expected counts:
```
zone                   5
agenti                 6
clienti                10
clienti_contacte       5
intervale_plata        2
intervale_plata_zile   8
zone_agenti            11
zone_intervale_plata   5
```

- [ ] **Step 5: Spot-check FK validity (no orphans)**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_distributie/oracle@localhost:1521/DISTRIBUTIE <<'EOF'
SELECT COUNT(*) AS orphans FROM clienti c WHERE NOT EXISTS (SELECT 1 FROM zone z WHERE z.id=c.id_zona);
EXIT
EOF
```
Expected: `ORPHANS` = `0`.

- [ ] **Step 6: Commit**

```bash
cd /Users/octav/MODBD && \
  git add modbd/oracle/ddl/11_load_distributie.sql && \
  git commit -m "data: load DISTRIBUTIE from CSVs (10 clients, 5 zones, 6 agents, 19 M:N rows)"
```

---

## Task 5: DDL CATALOG (lookups + ITEMS split CORE/EXTRA + V_ITEMS + triggers)

**Files:**
- Create: `modbd/oracle/ddl/12_ddl_catalog.sql`

- [ ] **Step 1: Write verification — no tables**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_catalog/oracle@localhost:1521/CATALOG <<'EOF'
SELECT COUNT(*) AS n_tables FROM user_tables;
SELECT COUNT(*) AS n_views FROM user_views;
EXIT
EOF
```
Expected: both `0`.

- [ ] **Step 2: Write the DDL**

Create `/Users/octav/MODBD/modbd/oracle/ddl/12_ddl_catalog.sql`:
```sql
-- =============================================================================
-- 12_ddl_catalog.sql
-- Schema CATALOG (sgbd_catalog): produse + lookups.
-- 4 lookup tables (BRANDS, ITEMS_CATEGORY, ITEMS_TYPE, ITEMS_SEASONS)
-- + ITEMS fragmentat vertical in ITEMS_CORE (8 col) + ITEMS_EXTRA (8 col)
-- + V_ITEMS (view de transparenta verticala, JOIN pe id)
-- + 3 triggere INSTEAD OF pe V_ITEMS pentru DML transparent.
-- =============================================================================

-- ------ Lookups ------
CREATE TABLE brands (
  id           NUMBER(19) PRIMARY KEY,
  code         VARCHAR2(3)   NOT NULL,
  brand        VARCHAR2(50),
  description  VARCHAR2(300),
  CONSTRAINT uk_brands_code UNIQUE (code)
);

CREATE TABLE items_category (
  id        NUMBER(19) PRIMARY KEY,
  code      VARCHAR2(2)  NOT NULL,
  category  VARCHAR2(50) NOT NULL,
  name      VARCHAR2(50) NOT NULL,
  CONSTRAINT uk_cat_code UNIQUE (code)
);

CREATE TABLE items_type (
  id           NUMBER(19) PRIMARY KEY,
  code         VARCHAR2(4),
  item_type    VARCHAR2(200),
  description  VARCHAR2(600),
  CONSTRAINT uk_type_code UNIQUE (code)
);

CREATE TABLE items_seasons (
  id           NUMBER(19) PRIMARY KEY,
  code         VARCHAR2(120),
  description  VARCHAR2(40),
  season_year  VARCHAR2(8),    -- 'year' e cuvant rezervat in Oracle
  active       NUMBER(10),
  CONSTRAINT uk_seasons_code UNIQUE (code),
  CONSTRAINT ck_seasons_active CHECK (active IN (0,1))
);

-- ------ ITEMS fragmentat vertical ------
CREATE TABLE items_core (
  id            NUMBER(19) PRIMARY KEY,
  item_code     VARCHAR2(50)  NOT NULL,
  item_name     VARCHAR2(350) NOT NULL,
  brand_id      NUMBER(19),
  season_id     NUMBER(19),
  item_type_id  NUMBER(19),
  category_id   NUMBER(19),
  active        NUMBER,
  CONSTRAINT uk_items_code UNIQUE (item_code),
  CONSTRAINT fk_items_brand    FOREIGN KEY (brand_id)     REFERENCES brands(id),
  CONSTRAINT fk_items_season   FOREIGN KEY (season_id)    REFERENCES items_seasons(id),
  CONSTRAINT fk_items_type     FOREIGN KEY (item_type_id) REFERENCES items_type(id),
  CONSTRAINT fk_items_category FOREIGN KEY (category_id)  REFERENCES items_category(id)
);

CREATE TABLE items_extra (
  id               NUMBER(19) PRIMARY KEY,
  item_description VARCHAR2(1000),
  vat              BINARY_DOUBLE,
  last_cost_price  NUMBER(9,2),
  main_barcode     VARCHAR2(20),
  supplier_code    VARCHAR2(60),
  weight           NUMBER(9,2),
  um               VARCHAR2(10),
  CONSTRAINT fk_items_extra_core FOREIGN KEY (id) REFERENCES items_core(id) ON DELETE CASCADE
);

-- ------ View de transparenta verticala (JOIN dupa id) ------
CREATE OR REPLACE VIEW v_items AS
SELECT c.id, c.item_code, c.item_name, e.item_description,
       c.brand_id, c.season_id, c.item_type_id, c.category_id,
       e.vat, e.last_cost_price, e.main_barcode, e.supplier_code,
       e.weight, e.um, c.active
FROM   items_core c
       JOIN items_extra e ON e.id = c.id;

-- ------ Triggere INSTEAD OF pe V_ITEMS ------
CREATE OR REPLACE TRIGGER trg_v_items_ins
INSTEAD OF INSERT ON v_items
FOR EACH ROW
BEGIN
  INSERT INTO items_core (id, item_code, item_name, brand_id, season_id, item_type_id, category_id, active)
    VALUES (:NEW.id, :NEW.item_code, :NEW.item_name, :NEW.brand_id,
            :NEW.season_id, :NEW.item_type_id, :NEW.category_id, :NEW.active);
  INSERT INTO items_extra (id, item_description, vat, last_cost_price, main_barcode, supplier_code, weight, um)
    VALUES (:NEW.id, :NEW.item_description, :NEW.vat, :NEW.last_cost_price,
            :NEW.main_barcode, :NEW.supplier_code, :NEW.weight, :NEW.um);
END;
/

CREATE OR REPLACE TRIGGER trg_v_items_upd
INSTEAD OF UPDATE ON v_items
FOR EACH ROW
BEGIN
  UPDATE items_core SET
    item_code = :NEW.item_code, item_name = :NEW.item_name,
    brand_id = :NEW.brand_id, season_id = :NEW.season_id,
    item_type_id = :NEW.item_type_id, category_id = :NEW.category_id,
    active = :NEW.active
  WHERE id = :OLD.id;
  UPDATE items_extra SET
    item_description = :NEW.item_description, vat = :NEW.vat,
    last_cost_price = :NEW.last_cost_price, main_barcode = :NEW.main_barcode,
    supplier_code = :NEW.supplier_code, weight = :NEW.weight, um = :NEW.um
  WHERE id = :OLD.id;
END;
/

CREATE OR REPLACE TRIGGER trg_v_items_del
INSTEAD OF DELETE ON v_items
FOR EACH ROW
BEGIN
  DELETE FROM items_core WHERE id = :OLD.id;  -- ON DELETE CASCADE va sterge si items_extra
END;
/
```

- [ ] **Step 3: Run the DDL**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_catalog/oracle@localhost:1521/CATALOG < /Users/octav/MODBD/modbd/oracle/ddl/12_ddl_catalog.sql
```
Expected: 6× `Table created.`, 1× `View created.`, 3× `Trigger created.`

- [ ] **Step 4: Re-run verification — 6 tables + 1 view + 3 triggers**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_catalog/oracle@localhost:1521/CATALOG <<'EOF'
SELECT 'tables' AS what, COUNT(*) AS n FROM user_tables
UNION ALL SELECT 'views', COUNT(*) FROM user_views
UNION ALL SELECT 'triggers', COUNT(*) FROM user_triggers;
EXIT
EOF
```
Expected: tables=6, views=1, triggers=3.

- [ ] **Step 5: Commit**

```bash
cd /Users/octav/MODBD && \
  git add modbd/oracle/ddl/12_ddl_catalog.sql && \
  git commit -m "feat: DDL CATALOG (lookups + ITEMS vertical fragments + V_ITEMS + INSTEAD OF triggers)"
```

---

## Task 6: Load CATALOG (split ITEMS into CORE/EXTRA)

**Files:**
- Create: `modbd/oracle/ddl/13_load_catalog.sql`

- [ ] **Step 1: Write verification — tables empty**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_catalog/oracle@localhost:1521/CATALOG <<'EOF'
SELECT 'brands' AS t, COUNT(*) AS n FROM brands
UNION ALL SELECT 'items_category', COUNT(*) FROM items_category
UNION ALL SELECT 'items_type', COUNT(*) FROM items_type
UNION ALL SELECT 'items_seasons', COUNT(*) FROM items_seasons
UNION ALL SELECT 'items_core', COUNT(*) FROM items_core
UNION ALL SELECT 'items_extra', COUNT(*) FROM items_extra;
EXIT
EOF
```
Expected: all 0.

- [ ] **Step 2: Write the load script**

Create `/Users/octav/MODBD/modbd/oracle/ddl/13_load_catalog.sql`:
```sql
-- =============================================================================
-- 13_load_catalog.sql
-- Incarca CATALOG: 4 lookup-uri + ITEMS split vertical in CORE/EXTRA.
-- ITEMS.csv contine toate 15 coloane; le distribuim in cele 2 fragmente prin
-- 2 INSERT-uri din acelasi external table.
-- =============================================================================

-- BRANDS
CREATE TABLE ext_brands (
  id NUMBER(19), code VARCHAR2(3), brand VARCHAR2(50), description VARCHAR2(300)
)
ORGANIZATION EXTERNAL (
  TYPE ORACLE_LOADER DEFAULT DIRECTORY csv_dir
  ACCESS PARAMETERS (
    RECORDS DELIMITED BY NEWLINE CHARACTERSET UTF8 SKIP 1
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    MISSING FIELD VALUES ARE NULL
  )
  LOCATION ('BRANDS.csv')
) REJECT LIMIT UNLIMITED;

INSERT INTO brands (id, code, brand, description)
SELECT id, code,
       NULLIF(brand, 'NULL'),
       NULLIF(description, 'NULL')
FROM ext_brands;
DROP TABLE ext_brands;

-- ITEMS_CATEGORY (CSV: id, code, category, name)
CREATE TABLE ext_items_cat (
  id NUMBER(19), code VARCHAR2(2), category VARCHAR2(50), name VARCHAR2(50)
)
ORGANIZATION EXTERNAL (
  TYPE ORACLE_LOADER DEFAULT DIRECTORY csv_dir
  ACCESS PARAMETERS (
    RECORDS DELIMITED BY NEWLINE CHARACTERSET UTF8 SKIP 1
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    MISSING FIELD VALUES ARE NULL
  )
  LOCATION ('ITEMS_CATEGORY.csv')
) REJECT LIMIT UNLIMITED;

INSERT INTO items_category SELECT * FROM ext_items_cat;
DROP TABLE ext_items_cat;

-- ITEMS_TYPE
CREATE TABLE ext_items_type (
  id NUMBER(19), code VARCHAR2(4), item_type VARCHAR2(200), description VARCHAR2(600)
)
ORGANIZATION EXTERNAL (
  TYPE ORACLE_LOADER DEFAULT DIRECTORY csv_dir
  ACCESS PARAMETERS (
    RECORDS DELIMITED BY NEWLINE CHARACTERSET UTF8 SKIP 1
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    MISSING FIELD VALUES ARE NULL
  )
  LOCATION ('ITEMS_TYPE.csv')
) REJECT LIMIT UNLIMITED;

INSERT INTO items_type (id, code, item_type, description)
SELECT id, code, item_type, NULLIF(description, 'NULL') FROM ext_items_type;
DROP TABLE ext_items_type;

-- ITEMS_SEASONS (note: CSV col 'YEAR' → table col 'season_year')
CREATE TABLE ext_items_seasons (
  id NUMBER(19), code VARCHAR2(120), description VARCHAR2(40),
  season_year VARCHAR2(8), active NUMBER(10)
)
ORGANIZATION EXTERNAL (
  TYPE ORACLE_LOADER DEFAULT DIRECTORY csv_dir
  ACCESS PARAMETERS (
    RECORDS DELIMITED BY NEWLINE CHARACTERSET UTF8 SKIP 1
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' (id,code,description,year,active)
    MISSING FIELD VALUES ARE NULL
  )
  LOCATION ('ITEMS_SEASONS.csv')
) REJECT LIMIT UNLIMITED;

INSERT INTO items_seasons (id, code, description, season_year, active)
SELECT id, code, description, season_year, active FROM ext_items_seasons;
DROP TABLE ext_items_seasons;

-- ITEMS (15 coloane CSV → split CORE 8 + EXTRA 8 share id)
CREATE TABLE ext_items (
  id NUMBER(19), item_code VARCHAR2(50), item_name VARCHAR2(350),
  item_description VARCHAR2(1000),
  brand_id VARCHAR2(20), season_id VARCHAR2(20),
  item_type_id VARCHAR2(20), category_id VARCHAR2(20),
  vat VARCHAR2(40), last_cost_price VARCHAR2(40),
  main_barcode VARCHAR2(20), supplier_code VARCHAR2(60),
  weight VARCHAR2(40), um VARCHAR2(10), active VARCHAR2(10)
)
ORGANIZATION EXTERNAL (
  TYPE ORACLE_LOADER DEFAULT DIRECTORY csv_dir
  ACCESS PARAMETERS (
    RECORDS DELIMITED BY NEWLINE CHARACTERSET UTF8 SKIP 1
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    MISSING FIELD VALUES ARE NULL
  )
  LOCATION ('ITEMS.csv')
) REJECT LIMIT UNLIMITED;

-- Populez CORE
INSERT INTO items_core (id, item_code, item_name, brand_id, season_id, item_type_id, category_id, active)
SELECT id, item_code, item_name,
       CAST(NULLIF(brand_id,    'NULL') AS NUMBER(19)),
       CAST(NULLIF(season_id,   'NULL') AS NUMBER(19)),
       CAST(NULLIF(item_type_id,'NULL') AS NUMBER(19)),
       CAST(NULLIF(category_id, 'NULL') AS NUMBER(19)),
       CAST(NULLIF(active, 'NULL') AS NUMBER)
FROM ext_items;

-- Populez EXTRA
INSERT INTO items_extra (id, item_description, vat, last_cost_price, main_barcode, supplier_code, weight, um)
SELECT id,
       NULLIF(item_description, 'NULL'),
       CAST(NULLIF(vat, 'NULL') AS BINARY_DOUBLE),
       CAST(NULLIF(last_cost_price, 'NULL') AS NUMBER(9,2)),
       NULLIF(main_barcode, 'NULL'),
       NULLIF(supplier_code, 'NULL'),
       CAST(NULLIF(weight, 'NULL') AS NUMBER(9,2)),
       NULLIF(um, 'NULL')
FROM ext_items;
DROP TABLE ext_items;

COMMIT;
```

- [ ] **Step 3: Run the load**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_catalog/oracle@localhost:1521/CATALOG < /Users/octav/MODBD/modbd/oracle/ddl/13_load_catalog.sql
```
Expected: Tables created/dropped, INSERTs with row counts, final `Commit complete.`

- [ ] **Step 4: Verify counts**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_catalog/oracle@localhost:1521/CATALOG <<'EOF'
SELECT 'brands' AS t, COUNT(*) AS n FROM brands
UNION ALL SELECT 'items_category', COUNT(*) FROM items_category
UNION ALL SELECT 'items_type', COUNT(*) FROM items_type
UNION ALL SELECT 'items_seasons', COUNT(*) FROM items_seasons
UNION ALL SELECT 'items_core', COUNT(*) FROM items_core
UNION ALL SELECT 'items_extra', COUNT(*) FROM items_extra
UNION ALL SELECT 'v_items (transparenta)', COUNT(*) FROM v_items;
EXIT
EOF
```
Expected:
```
brands                  131
items_category          15
items_type              3
items_seasons           17
items_core              3192
items_extra             3192
v_items                 3192
```

- [ ] **Step 5: Test V_ITEMS DML transparency via INSTEAD OF trigger**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_catalog/oracle@localhost:1521/CATALOG <<'EOF'
INSERT INTO v_items (id, item_code, item_name, item_description, brand_id, season_id, item_type_id, category_id, vat, last_cost_price, main_barcode, supplier_code, weight, um, active)
VALUES (9999999, 'TEST_001', 'Produs Test', 'Descriere test', NULL, NULL, NULL, NULL, 19.0, 10.00, 'BAR001', 'SUP1', 0.5, 'BUC', 1);
SELECT COUNT(*) FROM items_core WHERE id=9999999;
SELECT COUNT(*) FROM items_extra WHERE id=9999999;
DELETE FROM v_items WHERE id=9999999;
SELECT COUNT(*) FROM items_core WHERE id=9999999;
SELECT COUNT(*) FROM items_extra WHERE id=9999999;
ROLLBACK;
EXIT
EOF
```
Expected: `1` after insert (both fragments), `0` after delete (both, cascade).

- [ ] **Step 6: Commit**

```bash
cd /Users/octav/MODBD && \
  git add modbd/oracle/ddl/13_load_catalog.sql && \
  git commit -m "data: load CATALOG (131 brands, 3192 items split into CORE/EXTRA)"
```

---

## Task 7: DDL VANZARI fragmente fizice (FISE_RO/EXT + LINII_RO/EXT)

**Files:**
- Create: `modbd/oracle/ddl/14_ddl_vanzari_fragments.sql`

- [ ] **Step 1: Verify no tables yet**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_vanzari/oracle@localhost:1521/VANZARI <<'EOF'
SELECT COUNT(*) AS n FROM user_tables;
EXIT
EOF
```
Expected: `0`.

- [ ] **Step 2: Write the DDL**

Create `/Users/octav/MODBD/modbd/oracle/ddl/14_ddl_vanzari_fragments.sql`:
```sql
-- =============================================================================
-- 14_ddl_vanzari_fragments.sql
-- Schema VANZARI: 4 fragmente fizice (FISE_CLIENTI_RO/EXT + LINII_DOC_RO/EXT).
-- FK-urile cross-PDB (catre MV_CLIENTI si MV_ITEMS_CORE) le adaugam mai tarziu,
-- dupa ce MV-urile sunt populate (Task 12). FK-urile intra-PDB le adaugam acum.
-- =============================================================================

-- Fragment H primar 1: moneda = 'RON'
CREATE TABLE fise_clienti_ro (
  id                  NUMBER(19) PRIMARY KEY,
  nr_document         VARCHAR2(30) NOT NULL,
  nr_doc_initial      VARCHAR2(30),
  tip_doc             CHAR(1)      NOT NULL,
  doc_type_xrp        CHAR(3)      NOT NULL,
  data_doc_efectiva   DATE         NOT NULL,
  data_scad           DATE,
  semn                NUMBER(2)    NOT NULL,
  moneda              VARCHAR2(10) NOT NULL,
  amount_doc          NUMBER(17,2) NOT NULL,
  amount_doc_ron      NUMBER(17,2) NOT NULL,
  plata_prin          VARCHAR2(20),
  cod_client          VARCHAR2(60) NOT NULL,
  denumire_client     VARCHAR2(200) NOT NULL,
  clasa_client        VARCHAR2(20) NOT NULL,
  CONSTRAINT uk_fise_ro_doc UNIQUE (nr_document, doc_type_xrp),
  CONSTRAINT ck_fise_ro_mon CHECK (moneda = 'RON'),
  CONSTRAINT ck_fise_ro_tipdoc CHECK (tip_doc IN ('F','I')),
  CONSTRAINT ck_fise_ro_xrp CHECK (doc_type_xrp IN ('INV','PMT','CRM','PPM','REF','RPM','DRM','VRF')),
  CONSTRAINT ck_fise_ro_semn CHECK (semn IN (-1, 1))
);

-- Fragment H primar 2: moneda != 'RON' (EUR/CZK/USD)
CREATE TABLE fise_clienti_ext (
  id                  NUMBER(19) PRIMARY KEY,
  nr_document         VARCHAR2(30) NOT NULL,
  nr_doc_initial      VARCHAR2(30),
  tip_doc             CHAR(1)      NOT NULL,
  doc_type_xrp        CHAR(3)      NOT NULL,
  data_doc_efectiva   DATE         NOT NULL,
  data_scad           DATE,
  semn                NUMBER(2)    NOT NULL,
  moneda              VARCHAR2(10) NOT NULL,
  amount_doc          NUMBER(17,2) NOT NULL,
  amount_doc_ron      NUMBER(17,2) NOT NULL,
  plata_prin          VARCHAR2(20),
  cod_client          VARCHAR2(60) NOT NULL,
  denumire_client     VARCHAR2(200) NOT NULL,
  clasa_client        VARCHAR2(20) NOT NULL,
  CONSTRAINT uk_fise_ext_doc UNIQUE (nr_document, doc_type_xrp),
  CONSTRAINT ck_fise_ext_mon CHECK (moneda <> 'RON'),
  CONSTRAINT ck_fise_ext_tipdoc CHECK (tip_doc IN ('F','I')),
  CONSTRAINT ck_fise_ext_xrp CHECK (doc_type_xrp IN ('INV','PMT','CRM','PPM','REF','RPM','DRM','VRF')),
  CONSTRAINT ck_fise_ext_semn CHECK (semn IN (-1, 1))
);

-- Fragment H derivat 1: linii care apartin de FISE_CLIENTI_RO
CREATE TABLE linii_doc_ro (
  id                          NUMBER(19) PRIMARY KEY,
  doc_type_xrp                CHAR(3)      NOT NULL,
  nr_document                 VARCHAR2(30) NOT NULL,
  item_code                   VARCHAR2(50) NOT NULL,
  item_qty                    NUMBER(13,2),
  xrp_doc_valoare_fara_tva    NUMBER(9,2),
  xrp_doc_tva                 NUMBER(9,2),
  xrp_doc_procent_tva         NUMBER(9,2),
  xrp_doc_valoare_totala      NUMBER(9,2),
  xrp_linie_is_with_vat       VARCHAR2(40),
  xrp_linie_valoare_fara_tva  NUMBER(9,2),
  xrp_linie_tva               NUMBER(9,2),
  xrp_linie_proc_tva          NUMBER(9,2),
  CONSTRAINT fk_lin_ro_fise FOREIGN KEY (nr_document, doc_type_xrp)
    REFERENCES fise_clienti_ro(nr_document, doc_type_xrp)
);

-- Fragment H derivat 2: linii care apartin de FISE_CLIENTI_EXT
CREATE TABLE linii_doc_ext (
  id                          NUMBER(19) PRIMARY KEY,
  doc_type_xrp                CHAR(3)      NOT NULL,
  nr_document                 VARCHAR2(30) NOT NULL,
  item_code                   VARCHAR2(50) NOT NULL,
  item_qty                    NUMBER(13,2),
  xrp_doc_valoare_fara_tva    NUMBER(9,2),
  xrp_doc_tva                 NUMBER(9,2),
  xrp_doc_procent_tva         NUMBER(9,2),
  xrp_doc_valoare_totala      NUMBER(9,2),
  xrp_linie_is_with_vat       VARCHAR2(40),
  xrp_linie_valoare_fara_tva  NUMBER(9,2),
  xrp_linie_tva               NUMBER(9,2),
  xrp_linie_proc_tva          NUMBER(9,2),
  CONSTRAINT fk_lin_ext_fise FOREIGN KEY (nr_document, doc_type_xrp)
    REFERENCES fise_clienti_ext(nr_document, doc_type_xrp)
);
```

- [ ] **Step 3: Run the DDL**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_vanzari/oracle@localhost:1521/VANZARI < /Users/octav/MODBD/modbd/oracle/ddl/14_ddl_vanzari_fragments.sql
```
Expected: 4× `Table created.`

- [ ] **Step 4: Re-run verification — 4 tables**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_vanzari/oracle@localhost:1521/VANZARI <<'EOF'
SELECT table_name FROM user_tables ORDER BY table_name;
EXIT
EOF
```
Expected: `FISE_CLIENTI_EXT`, `FISE_CLIENTI_RO`, `LINII_DOC_EXT`, `LINII_DOC_RO`.

- [ ] **Step 5: Commit**

```bash
cd /Users/octav/MODBD && \
  git add modbd/oracle/ddl/14_ddl_vanzari_fragments.sql && \
  git commit -m "feat: DDL VANZARI fragments (FISE RO/EXT + LINII RO/EXT derived)"
```

---

## Task 8: Load VANZARI (split FISE + LINII per Moneda)

**Files:**
- Create: `modbd/oracle/ddl/15_load_vanzari.sql`

- [ ] **Step 1: Verify tables empty**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_vanzari/oracle@localhost:1521/VANZARI <<'EOF'
SELECT 'fise_ro' AS t, COUNT(*) AS n FROM fise_clienti_ro
UNION ALL SELECT 'fise_ext', COUNT(*) FROM fise_clienti_ext
UNION ALL SELECT 'lin_ro', COUNT(*) FROM linii_doc_ro
UNION ALL SELECT 'lin_ext', COUNT(*) FROM linii_doc_ext;
EXIT
EOF
```
Expected: all `0`.

- [ ] **Step 2: Write load script with split logic**

Create `/Users/octav/MODBD/modbd/oracle/ddl/15_load_vanzari.sql`:
```sql
-- =============================================================================
-- 15_load_vanzari.sql
-- Incarca cele 4 fragmente fizice ale VANZARI prin 2 external tables:
--  - ext_fise_all (DOCS_HEADERS.csv) -> INSERT cu WHERE moneda='RON' / <>'RON'
--  - ext_linii_all (DOCS_LINES.csv) -> INSERT cu join pe nr_doc+doc_type_xrp
--    catre fragmentul de fise corespunzator
-- =============================================================================

-- External table pentru documente
CREATE TABLE ext_fise_all (
  id                  NUMBER(19),
  nr_document         VARCHAR2(30),
  nr_doc_initial      VARCHAR2(30),
  tip_doc             CHAR(1),
  doc_type_xrp        CHAR(3),
  data_doc_efectiva   VARCHAR2(20),
  data_scad           VARCHAR2(20),
  semn                NUMBER(2),
  moneda              VARCHAR2(10),
  amount_doc          NUMBER(17,2),
  amount_doc_ron      NUMBER(17,2),
  plata_prin          VARCHAR2(20),
  cod_client          VARCHAR2(60),
  denumire_client     VARCHAR2(200),
  clasa_client        VARCHAR2(20)
)
ORGANIZATION EXTERNAL (
  TYPE ORACLE_LOADER DEFAULT DIRECTORY csv_dir
  ACCESS PARAMETERS (
    RECORDS DELIMITED BY NEWLINE CHARACTERSET UTF8 SKIP 1
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    MISSING FIELD VALUES ARE NULL
  )
  LOCATION ('DOCS_HEADERS.csv')
) REJECT LIMIT UNLIMITED;

-- INSERT in FISE_CLIENTI_RO (filter moneda='RON')
INSERT INTO fise_clienti_ro (id, nr_document, nr_doc_initial, tip_doc, doc_type_xrp,
                              data_doc_efectiva, data_scad, semn, moneda,
                              amount_doc, amount_doc_ron, plata_prin,
                              cod_client, denumire_client, clasa_client)
SELECT id, nr_document, NULLIF(nr_doc_initial, 'NULL'), tip_doc, doc_type_xrp,
       TO_DATE(data_doc_efectiva, 'YYYY-MM-DD'),
       CASE WHEN data_scad='NULL' THEN NULL ELSE TO_DATE(data_scad, 'YYYY-MM-DD') END,
       semn, moneda, amount_doc, amount_doc_ron,
       NULLIF(plata_prin, 'NULL'),
       cod_client, denumire_client, clasa_client
FROM ext_fise_all
WHERE moneda = 'RON';

-- INSERT in FISE_CLIENTI_EXT (filter moneda<>'RON')
INSERT INTO fise_clienti_ext (id, nr_document, nr_doc_initial, tip_doc, doc_type_xrp,
                               data_doc_efectiva, data_scad, semn, moneda,
                               amount_doc, amount_doc_ron, plata_prin,
                               cod_client, denumire_client, clasa_client)
SELECT id, nr_document, NULLIF(nr_doc_initial, 'NULL'), tip_doc, doc_type_xrp,
       TO_DATE(data_doc_efectiva, 'YYYY-MM-DD'),
       CASE WHEN data_scad='NULL' THEN NULL ELSE TO_DATE(data_scad, 'YYYY-MM-DD') END,
       semn, moneda, amount_doc, amount_doc_ron,
       NULLIF(plata_prin, 'NULL'),
       cod_client, denumire_client, clasa_client
FROM ext_fise_all
WHERE moneda <> 'RON';

DROP TABLE ext_fise_all;

-- External table pentru linii
CREATE TABLE ext_linii_all (
  id                          NUMBER(19),
  doc_type_xrp                CHAR(3),
  nr_document                 VARCHAR2(30),
  item_code                   VARCHAR2(50),
  item_qty                    NUMBER(13,2),
  xrp_doc_valoare_fara_tva    NUMBER(9,2),
  xrp_doc_tva                 NUMBER(9,2),
  xrp_doc_procent_tva         NUMBER(9,2),
  xrp_doc_valoare_totala      NUMBER(9,2),
  xrp_linie_is_with_vat       VARCHAR2(40),
  xrp_linie_valoare_fara_tva  NUMBER(9,2),
  xrp_linie_tva               NUMBER(9,2),
  xrp_linie_proc_tva          NUMBER(9,2)
)
ORGANIZATION EXTERNAL (
  TYPE ORACLE_LOADER DEFAULT DIRECTORY csv_dir
  ACCESS PARAMETERS (
    RECORDS DELIMITED BY NEWLINE CHARACTERSET UTF8 SKIP 1
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    MISSING FIELD VALUES ARE NULL
  )
  LOCATION ('DOCS_LINES.csv')
) REJECT LIMIT UNLIMITED;

-- INSERT in LINII_DOC_RO (linii al caror header e in fise_clienti_ro)
INSERT INTO linii_doc_ro
SELECT l.* FROM ext_linii_all l
WHERE EXISTS (
  SELECT 1 FROM fise_clienti_ro f
  WHERE f.nr_document = l.nr_document AND f.doc_type_xrp = l.doc_type_xrp
);

-- INSERT in LINII_DOC_EXT (linii al caror header e in fise_clienti_ext)
INSERT INTO linii_doc_ext
SELECT l.* FROM ext_linii_all l
WHERE EXISTS (
  SELECT 1 FROM fise_clienti_ext f
  WHERE f.nr_document = l.nr_document AND f.doc_type_xrp = l.doc_type_xrp
);

DROP TABLE ext_linii_all;
COMMIT;
```

- [ ] **Step 3: Run the load**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_vanzari/oracle@localhost:1521/VANZARI < /Users/octav/MODBD/modbd/oracle/ddl/15_load_vanzari.sql
```
Expected: external tables created, 4 INSERTs with row counts (sum FISE=2048, sum LINII=5598), final `Commit complete.`

- [ ] **Step 4: Verify split**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_vanzari/oracle@localhost:1521/VANZARI <<'EOF'
SELECT 'fise_ro' AS t, COUNT(*) AS n FROM fise_clienti_ro
UNION ALL SELECT 'fise_ext', COUNT(*) FROM fise_clienti_ext
UNION ALL SELECT 'lin_ro', COUNT(*) FROM linii_doc_ro
UNION ALL SELECT 'lin_ext', COUNT(*) FROM linii_doc_ext;
SELECT SUM(n) AS total_fise FROM (
  SELECT COUNT(*) AS n FROM fise_clienti_ro UNION ALL SELECT COUNT(*) FROM fise_clienti_ext
);
SELECT SUM(n) AS total_linii FROM (
  SELECT COUNT(*) AS n FROM linii_doc_ro UNION ALL SELECT COUNT(*) FROM linii_doc_ext
);
EXIT
EOF
```
Expected: sums equal `2048` (FISE) and `5598` (LINII). RO should dominate (~80% of total).

- [ ] **Step 5: Verify fragmentation disjuncție (no overlap)**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_vanzari/oracle@localhost:1521/VANZARI <<'EOF'
SELECT COUNT(*) AS overlap FROM fise_clienti_ro WHERE moneda <> 'RON';
SELECT COUNT(*) AS overlap FROM fise_clienti_ext WHERE moneda = 'RON';
EXIT
EOF
```
Expected: both `0`.

- [ ] **Step 6: Commit**

```bash
cd /Users/octav/MODBD && \
  git add modbd/oracle/ddl/15_load_vanzari.sql && \
  git commit -m "data: load VANZARI (FISE+LINII split per Moneda — 2048 docs, 5598 lines)"
```

---

## Task 9: Views UNION ALL + INSTEAD OF triggers (transparency on VANZARI)

**Files:**
- Create: `modbd/oracle/ddl/16_views_transparenta.sql`

- [ ] **Step 1: Verify no views yet**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_vanzari/oracle@localhost:1521/VANZARI <<'EOF'
SELECT COUNT(*) AS n FROM user_views;
EXIT
EOF
```
Expected: `0`.

- [ ] **Step 2: Write views + INSTEAD OF triggers**

Create `/Users/octav/MODBD/modbd/oracle/ddl/16_views_transparenta.sql`:
```sql
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
  -- Mutare cross-fragment dacă moneda se schimba din RON ↔ non-RON
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
```

- [ ] **Step 3: Run script**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_vanzari/oracle@localhost:1521/VANZARI < /Users/octav/MODBD/modbd/oracle/ddl/16_views_transparenta.sql
```
Expected: 2× `View created.`, 5× `Trigger created.`

- [ ] **Step 4: Verify transparency: V_FISE_CLIENTI total = sum of fragments**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_vanzari/oracle@localhost:1521/VANZARI <<'EOF'
SELECT COUNT(*) AS v_fise FROM v_fise_clienti;
SELECT COUNT(*) AS sum_fragments FROM (
  SELECT id FROM fise_clienti_ro UNION ALL SELECT id FROM fise_clienti_ext
);
SELECT COUNT(*) AS v_linii FROM v_linii_doc;
EXIT
EOF
```
Expected: `V_FISE` = `2048`, `SUM_FRAGMENTS` = `2048`, `V_LINII` = `5598`.

- [ ] **Step 5: Commit**

```bash
cd /Users/octav/MODBD && \
  git add modbd/oracle/ddl/16_views_transparenta.sql && \
  git commit -m "feat: transparency views (UNION ALL) + INSTEAD OF triggers for FISE + LINII"
```

---

## Task 10: MV logs pe master PDBs (DISTRIBUTIE + CATALOG)

**Files:**
- Create: `modbd/oracle/ddl/17_mv_logs.sql`

- [ ] **Step 1: Verify no MV logs yet**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_distributie/oracle@localhost:1521/DISTRIBUTIE <<'EOF'
SELECT COUNT(*) AS n FROM user_mview_logs;
EXIT
EOF
```
Expected: `0`. Same for CATALOG.

- [ ] **Step 2: Write the script**

Create `/Users/octav/MODBD/modbd/oracle/ddl/17_mv_logs.sql`:
```sql
-- =============================================================================
-- 17_mv_logs.sql
-- MV logs pe tabelele care vor fi replicate cross-PDB (DISTRIBUTIE + CATALOG).
-- WITH PRIMARY KEY, ROWID, SEQUENCE INCLUDING NEW VALUES = config standard
-- pentru REFRESH FAST sa functioneze in toate cazurile (inclusiv subqueries).
-- =============================================================================

-- IMPORTANT: scriptul presupune rulare ca SYS (sau cu privilege),
-- alternand intre PDB-uri prin ALTER SESSION.

ALTER SESSION SET CONTAINER = DISTRIBUTIE;
ALTER SESSION SET CURRENT_SCHEMA = sgbd_distributie;

CREATE MATERIALIZED VIEW LOG ON clienti
  WITH PRIMARY KEY, ROWID, SEQUENCE INCLUDING NEW VALUES;

CREATE MATERIALIZED VIEW LOG ON zone
  WITH PRIMARY KEY, ROWID, SEQUENCE INCLUDING NEW VALUES;

ALTER SESSION SET CONTAINER = CATALOG;
ALTER SESSION SET CURRENT_SCHEMA = sgbd_catalog;

CREATE MATERIALIZED VIEW LOG ON items_core
  WITH PRIMARY KEY, ROWID, SEQUENCE INCLUDING NEW VALUES;

CREATE MATERIALIZED VIEW LOG ON brands
  WITH PRIMARY KEY, ROWID, SEQUENCE INCLUDING NEW VALUES;

CREATE MATERIALIZED VIEW LOG ON items_category
  WITH PRIMARY KEY, ROWID, SEQUENCE INCLUDING NEW VALUES;

CREATE MATERIALIZED VIEW LOG ON items_type
  WITH PRIMARY KEY, ROWID, SEQUENCE INCLUDING NEW VALUES;

CREATE MATERIALIZED VIEW LOG ON items_seasons
  WITH PRIMARY KEY, ROWID, SEQUENCE INCLUDING NEW VALUES;
```

- [ ] **Step 3: Run as SYS**

```bash
docker exec -i oracle-modbd sqlplus -s sys/ModbdSecret123@localhost:1521/XE as sysdba < /Users/octav/MODBD/modbd/oracle/ddl/17_mv_logs.sql
```
Expected: 7× `Materialized view log created.`

- [ ] **Step 4: Verify count of MV logs per PDB**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_distributie/oracle@localhost:1521/DISTRIBUTIE <<'EOF'
SELECT log_table FROM user_mview_logs ORDER BY log_table;
EXIT
EOF
docker exec -i oracle-modbd sqlplus -s sgbd_catalog/oracle@localhost:1521/CATALOG <<'EOF'
SELECT log_table FROM user_mview_logs ORDER BY log_table;
EXIT
EOF
```
Expected: DISTRIBUTIE shows 2 (CLIENTI, ZONE), CATALOG shows 5 (BRANDS, ITEMS_CATEGORY, ITEMS_CORE, ITEMS_SEASONS, ITEMS_TYPE).

- [ ] **Step 5: Commit**

```bash
cd /Users/octav/MODBD && \
  git add modbd/oracle/ddl/17_mv_logs.sql && \
  git commit -m "feat: MV logs on master tables (DISTRIBUTIE + CATALOG) for FAST refresh"
```

---

## Task 11: DB links din VANZARI + smoke test

**Files:**
- Create: `modbd/oracle/ddl/18_db_links.sql`

- [ ] **Step 1: Verify no DB links yet**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_vanzari/oracle@localhost:1521/VANZARI <<'EOF'
SELECT COUNT(*) AS n FROM user_db_links;
EXIT
EOF
```
Expected: `0`.

- [ ] **Step 2: Write the script**

Create `/Users/octav/MODBD/modbd/oracle/ddl/18_db_links.sql`:
```sql
-- =============================================================================
-- 18_db_links.sql
-- DB links private din VANZARI catre DISTRIBUTIE si CATALOG.
-- Conectare via EZCONNECT (host:port/service_name).
-- =============================================================================

CREATE DATABASE LINK lnk_distributie
  CONNECT TO sgbd_distributie IDENTIFIED BY oracle
  USING 'localhost:1521/DISTRIBUTIE';

CREATE DATABASE LINK lnk_catalog
  CONNECT TO sgbd_catalog IDENTIFIED BY oracle
  USING 'localhost:1521/CATALOG';
```

- [ ] **Step 3: Run**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_vanzari/oracle@localhost:1521/VANZARI < /Users/octav/MODBD/modbd/oracle/ddl/18_db_links.sql
```
Expected: 2× `Database link created.`

- [ ] **Step 4: Smoke test — query cross-PDB**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_vanzari/oracle@localhost:1521/VANZARI <<'EOF'
SELECT 'distributie' AS pdb, COUNT(*) AS n FROM clienti@lnk_distributie
UNION ALL
SELECT 'catalog', COUNT(*) FROM items_core@lnk_catalog;
EXIT
EOF
```
Expected: `distributie/10`, `catalog/3192`.

- [ ] **Step 5: Commit**

```bash
cd /Users/octav/MODBD && \
  git add modbd/oracle/ddl/18_db_links.sql && \
  git commit -m "feat: DB links VANZARI -> DISTRIBUTIE + CATALOG"
```

---

## Task 12: MV-uri replicate în VANZARI + FK-uri cross-PDB

**Files:**
- Create: `modbd/oracle/ddl/19_mvs_vanzari.sql`
- Create: `modbd/oracle/ddl/20_cross_pdb_fks.sql`

- [ ] **Step 1: Verify no MVs yet**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_vanzari/oracle@localhost:1521/VANZARI <<'EOF'
SELECT COUNT(*) AS n FROM user_mviews;
EXIT
EOF
```
Expected: `0`.

- [ ] **Step 2: Write MV script**

Create `/Users/octav/MODBD/modbd/oracle/ddl/19_mvs_vanzari.sql`:
```sql
-- =============================================================================
-- 19_mvs_vanzari.sql
-- MV-uri replicate in VANZARI care oglindesc tabelele master din DISTRIBUTIE
-- si CATALOG. Strategie: REFRESH FAST ON DEMAND (cross-PDB nu suporta ON COMMIT).
-- UK pe coloana de business permite FK-uri locale catre MV-uri (Task urmator).
-- =============================================================================

-- ===== Replici din DISTRIBUTIE =====
CREATE MATERIALIZED VIEW mv_clienti
  BUILD IMMEDIATE
  REFRESH FAST ON DEMAND
  WITH PRIMARY KEY
  AS SELECT * FROM clienti@lnk_distributie;
-- UK pentru a permite FK-uri pe cod_client
ALTER TABLE mv_clienti ADD CONSTRAINT uk_mv_clienti_cod UNIQUE (cod_client);

CREATE MATERIALIZED VIEW mv_zone
  BUILD IMMEDIATE
  REFRESH FAST ON DEMAND
  WITH PRIMARY KEY
  AS SELECT * FROM zone@lnk_distributie;

-- ===== Replici din CATALOG =====
CREATE MATERIALIZED VIEW mv_items_core
  BUILD IMMEDIATE
  REFRESH FAST ON DEMAND
  WITH PRIMARY KEY
  AS SELECT * FROM items_core@lnk_catalog;
ALTER TABLE mv_items_core ADD CONSTRAINT uk_mv_items_code UNIQUE (item_code);

CREATE MATERIALIZED VIEW mv_brands
  BUILD IMMEDIATE
  REFRESH FAST ON DEMAND
  WITH PRIMARY KEY
  AS SELECT * FROM brands@lnk_catalog;

CREATE MATERIALIZED VIEW mv_items_category
  BUILD IMMEDIATE
  REFRESH FAST ON DEMAND
  WITH PRIMARY KEY
  AS SELECT * FROM items_category@lnk_catalog;

CREATE MATERIALIZED VIEW mv_items_type
  BUILD IMMEDIATE
  REFRESH FAST ON DEMAND
  WITH PRIMARY KEY
  AS SELECT * FROM items_type@lnk_catalog;

CREATE MATERIALIZED VIEW mv_items_seasons
  BUILD IMMEDIATE
  REFRESH FAST ON DEMAND
  WITH PRIMARY KEY
  AS SELECT * FROM items_seasons@lnk_catalog;
```

- [ ] **Step 3: Run MV script**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_vanzari/oracle@localhost:1521/VANZARI < /Users/octav/MODBD/modbd/oracle/ddl/19_mvs_vanzari.sql
```
Expected: 7× `Materialized view created.` + 2× `Table altered.` (for UK constraints).

- [ ] **Step 4: Verify MVs populated**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_vanzari/oracle@localhost:1521/VANZARI <<'EOF'
SELECT 'mv_clienti' AS t, COUNT(*) AS n FROM mv_clienti
UNION ALL SELECT 'mv_zone', COUNT(*) FROM mv_zone
UNION ALL SELECT 'mv_items_core', COUNT(*) FROM mv_items_core
UNION ALL SELECT 'mv_brands', COUNT(*) FROM mv_brands
UNION ALL SELECT 'mv_items_category', COUNT(*) FROM mv_items_category
UNION ALL SELECT 'mv_items_type', COUNT(*) FROM mv_items_type
UNION ALL SELECT 'mv_items_seasons', COUNT(*) FROM mv_items_seasons;
EXIT
EOF
```
Expected: 10, 5, 3192, 131, 15, 3, 17.

- [ ] **Step 5: Write FK cross-PDB script**

Create `/Users/octav/MODBD/modbd/oracle/ddl/20_cross_pdb_fks.sql`:
```sql
-- =============================================================================
-- 20_cross_pdb_fks.sql
-- FK-uri locale catre MV-uri replicate, enforce constrangerile globale.
-- =============================================================================

ALTER TABLE fise_clienti_ro
  ADD CONSTRAINT fk_fise_ro_client
  FOREIGN KEY (cod_client) REFERENCES mv_clienti(cod_client);

ALTER TABLE fise_clienti_ext
  ADD CONSTRAINT fk_fise_ext_client
  FOREIGN KEY (cod_client) REFERENCES mv_clienti(cod_client);

ALTER TABLE linii_doc_ro
  ADD CONSTRAINT fk_lin_ro_item
  FOREIGN KEY (item_code) REFERENCES mv_items_core(item_code);

ALTER TABLE linii_doc_ext
  ADD CONSTRAINT fk_lin_ext_item
  FOREIGN KEY (item_code) REFERENCES mv_items_core(item_code);
```

- [ ] **Step 6: Run FK script**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_vanzari/oracle@localhost:1521/VANZARI < /Users/octav/MODBD/modbd/oracle/ddl/20_cross_pdb_fks.sql
```
Expected: 4× `Table altered.`

- [ ] **Step 7: Test FK enforcement (negative test)**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_vanzari/oracle@localhost:1521/VANZARI <<'EOF'
-- Should fail with ORA-02291 (parent key not found)
INSERT INTO fise_clienti_ro (id, nr_document, tip_doc, doc_type_xrp,
  data_doc_efectiva, semn, moneda, amount_doc, amount_doc_ron,
  cod_client, denumire_client, clasa_client)
VALUES (88888888, 'TEST_FK', 'F', 'INV', SYSDATE, 1, 'RON', 100, 100,
        'CLI_DOESNT_EXIST', 'Test', 'DISTR');
EXIT
EOF
```
Expected: `ORA-02291: integrity constraint (SGBD_VANZARI.FK_FISE_RO_CLIENT) violated`.

- [ ] **Step 8: Commit**

```bash
cd /Users/octav/MODBD && \
  git add modbd/oracle/ddl/19_mvs_vanzari.sql modbd/oracle/ddl/20_cross_pdb_fks.sql && \
  git commit -m "feat: replicated MVs in VANZARI + cross-PDB FKs (local refs to MVs)"
```

---

## Task 13: DBMS_SCHEDULER job — refresh MV-uri la 60s

**Files:**
- Create: `modbd/oracle/ddl/21_refresh_job.sql`

- [ ] **Step 1: Verify no job yet**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_vanzari/oracle@localhost:1521/VANZARI <<'EOF'
SELECT COUNT(*) AS n FROM user_scheduler_jobs WHERE job_name = 'JOB_REFRESH_MVS';
EXIT
EOF
```
Expected: `0`.

- [ ] **Step 2: Write the script**

Create `/Users/octav/MODBD/modbd/oracle/ddl/21_refresh_job.sql`:
```sql
-- =============================================================================
-- 21_refresh_job.sql
-- Job DBMS_SCHEDULER care refresh-ueaza FAST cele 7 MV-uri replicate la fiecare
-- 60 secunde. Acopera cerinta 'sincronizare relatii replicate' (1p).
-- =============================================================================

BEGIN
  DBMS_SCHEDULER.CREATE_JOB(
    job_name        => 'JOB_REFRESH_MVS',
    job_type        => 'PLSQL_BLOCK',
    job_action      => q'[BEGIN
      DBMS_MVIEW.REFRESH(
        'MV_CLIENTI,MV_ZONE,MV_ITEMS_CORE,MV_BRANDS,MV_ITEMS_CATEGORY,MV_ITEMS_TYPE,MV_ITEMS_SEASONS',
        method => 'FFFFFFF',
        atomic_refresh => FALSE);
    END;]',
    start_date      => SYSTIMESTAMP,
    repeat_interval => 'FREQ=SECONDLY;INTERVAL=60',
    enabled         => TRUE,
    comments        => 'Refresh FAST al MV-urilor replicate la 60s'
  );
END;
/
```

- [ ] **Step 3: Run**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_vanzari/oracle@localhost:1521/VANZARI < /Users/octav/MODBD/modbd/oracle/ddl/21_refresh_job.sql
```
Expected: `PL/SQL procedure successfully completed.`

- [ ] **Step 4: Verify job is enabled**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_vanzari/oracle@localhost:1521/VANZARI <<'EOF'
SELECT job_name, enabled, state, next_run_date FROM user_scheduler_jobs
WHERE job_name = 'JOB_REFRESH_MVS';
EXIT
EOF
```
Expected: enabled=TRUE, state=SCHEDULED.

- [ ] **Step 5: End-to-end sync test (60s round trip)**

Test that an insert in DISTRIBUTIE.clienti propagates to VANZARI.mv_clienti within ~70 seconds:
```bash
# Insert in master
docker exec -i oracle-modbd sqlplus -s sgbd_distributie/oracle@localhost:1521/DISTRIBUTIE <<'EOF'
INSERT INTO clienti (id, cod_client, denumire_client, tip_client, id_zona, start_date)
VALUES (999999, 'CLI_SYNC_TEST', 'Sync test', 'CLIENT', 1, SYSDATE);
COMMIT;
EXIT
EOF

# Wait 70s for job to fire
sleep 70

# Verify replica updated
docker exec -i oracle-modbd sqlplus -s sgbd_vanzari/oracle@localhost:1521/VANZARI <<'EOF'
SELECT COUNT(*) AS replicat FROM mv_clienti WHERE cod_client = 'CLI_SYNC_TEST';
EXIT
EOF

# Cleanup
docker exec -i oracle-modbd sqlplus -s sgbd_distributie/oracle@localhost:1521/DISTRIBUTIE <<'EOF'
DELETE FROM clienti WHERE cod_client = 'CLI_SYNC_TEST';
COMMIT;
EXIT
EOF
```
Expected: `REPLICAT` = `1` after sleep.

- [ ] **Step 6: Commit**

```bash
cd /Users/octav/MODBD && \
  git add modbd/oracle/ddl/21_refresh_job.sql && \
  git commit -m "feat: DBMS_SCHEDULER job refresh MVs at 60s interval"
```

---

## Task 14: Trigger agregat — coerență sumă document ↔ linii

**Files:**
- Create: `modbd/oracle/ddl/22_trigger_agregat.sql`

- [ ] **Step 1: Write the script**

Create `/Users/octav/MODBD/modbd/oracle/ddl/22_trigger_agregat.sql`:
```sql
-- =============================================================================
-- 22_trigger_agregat.sql
-- Propozitie de integritate cu agregat (curs cap. 3.4): suma valorilor de pe
-- liniile unui document trebuie sa fie egala (toleranta 0.01 RON) cu valoarea
-- totala a documentului.
-- Implementare: trigger AFTER STATEMENT pe linii_doc_*.
-- =============================================================================

CREATE OR REPLACE TRIGGER trg_coerenta_sum_ro
AFTER INSERT OR UPDATE OR DELETE ON linii_doc_ro
DECLARE
  CURSOR c IS
    SELECT f.nr_document, f.doc_type_xrp,
           f.amount_doc       AS doc_total,
           SUM(l.xrp_linie_valoare_fara_tva + l.xrp_linie_tva) AS sum_linii
    FROM fise_clienti_ro f
         JOIN linii_doc_ro l ON (l.nr_document, l.doc_type_xrp) = (f.nr_document, f.doc_type_xrp)
    GROUP BY f.nr_document, f.doc_type_xrp, f.amount_doc
    HAVING ABS(f.amount_doc - SUM(l.xrp_linie_valoare_fara_tva + l.xrp_linie_tva)) > 0.01;
BEGIN
  FOR r IN c LOOP
    RAISE_APPLICATION_ERROR(-20001,
      'Incoerenta suma pe ' || r.nr_document || '/' || r.doc_type_xrp ||
      ' (doc=' || r.doc_total || ' vs sum_linii=' || r.sum_linii || ')');
  END LOOP;
END;
/

CREATE OR REPLACE TRIGGER trg_coerenta_sum_ext
AFTER INSERT OR UPDATE OR DELETE ON linii_doc_ext
DECLARE
  CURSOR c IS
    SELECT f.nr_document, f.doc_type_xrp,
           f.amount_doc       AS doc_total,
           SUM(l.xrp_linie_valoare_fara_tva + l.xrp_linie_tva) AS sum_linii
    FROM fise_clienti_ext f
         JOIN linii_doc_ext l ON (l.nr_document, l.doc_type_xrp) = (f.nr_document, f.doc_type_xrp)
    GROUP BY f.nr_document, f.doc_type_xrp, f.amount_doc
    HAVING ABS(f.amount_doc - SUM(l.xrp_linie_valoare_fara_tva + l.xrp_linie_tva)) > 0.01;
BEGIN
  FOR r IN c LOOP
    RAISE_APPLICATION_ERROR(-20002,
      'Incoerenta suma EXT pe ' || r.nr_document || '/' || r.doc_type_xrp);
  END LOOP;
END;
/
```

- [ ] **Step 2: Run**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_vanzari/oracle@localhost:1521/VANZARI < /Users/octav/MODBD/modbd/oracle/ddl/22_trigger_agregat.sql
```
Expected: 2× `Trigger created.`

- [ ] **Step 3: Verify triggers exist**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_vanzari/oracle@localhost:1521/VANZARI <<'EOF'
SELECT trigger_name, status FROM user_triggers
WHERE trigger_name LIKE 'TRG_COERENTA%' ORDER BY trigger_name;
EXIT
EOF
```
Expected: 2 rows, both ENABLED.

> **Note**: existing data may not satisfy the constraint (CSV-urile pot conține mici discrepanțe între `amount_doc` și sum_linii). Trigger-ul se aplică doar la noi modificări. Dacă pasul 3 din task-ul de validare end-to-end (Task 17) eșuează, dezactivăm trigger-ul cu `ALTER TRIGGER ... DISABLE` și-l reactivam după ce reconcilizăm datele istorice.

- [ ] **Step 4: Commit**

```bash
cd /Users/octav/MODBD && \
  git add modbd/oracle/ddl/22_trigger_agregat.sql && \
  git commit -m "feat: aggregate constraint trigger (coherence doc total vs sum linii)"
```

---

## Task 15: Indexes + DBMS_STATS

**Files:**
- Create: `modbd/oracle/ddl/23_indexes_stats.sql`

- [ ] **Step 1: Write the script**

Create `/Users/octav/MODBD/modbd/oracle/ddl/23_indexes_stats.sql`:
```sql
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
```

- [ ] **Step 2: Run**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_vanzari/oracle@localhost:1521/VANZARI < /Users/octav/MODBD/modbd/oracle/ddl/23_indexes_stats.sql
```
Expected: 8× `Index created.`, `PL/SQL procedure successfully completed.`

- [ ] **Step 3: Verify**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_vanzari/oracle@localhost:1521/VANZARI <<'EOF'
SELECT index_name FROM user_indexes WHERE index_name LIKE 'IDX_%' ORDER BY index_name;
SELECT table_name, num_rows FROM user_tables ORDER BY table_name;
EXIT
EOF
```
Expected: 8 indexes listed; tables have `num_rows` populat (not NULL).

- [ ] **Step 4: Commit**

```bash
cd /Users/octav/MODBD && \
  git add modbd/oracle/ddl/23_indexes_stats.sql && \
  git commit -m "perf: indexes on fact tables + DBMS_STATS gathered"
```

---

## Task 16: Query complex — Top 10 agenți (RBO baseline + CBO default)

**Files:**
- Create: `modbd/oracle/ddl/30_query_complex.sql`

- [ ] **Step 1: Write the script — query + 3 EXPLAIN PLAN variants**

Create `/Users/octav/MODBD/modbd/oracle/ddl/30_query_complex.sql`:
```sql
-- =============================================================================
-- 30_query_complex.sql
-- Cererea complexa a proiectului: top 10 agenti dupa valoare vanduta in 2024,
-- defalcat pe zona si categorie produs.
-- Demonstreaza optimizare prin 3 EXPLAIN PLAN:
--   1. /*+ RULE */                 (Ingres-like RBO)
--   2. (no hint, default CBO)      (System R-like CBO)
--   3. /*+ DRIVING_SITE(...) */    (System R*-like distributed)
-- =============================================================================

SET LINESIZE 200
SET PAGESIZE 100

-- ====== 1. Query simplu (test ca returneaza rezultate) ======
PROMPT === 1. Query results ===

SELECT a.nume_agent, z.den_zona, c.name AS categorie,
       SUM(ld.xrp_linie_valoare_fara_tva) AS total_2024
FROM   v_fise_clienti f
       JOIN v_linii_doc ld
            ON ld.nr_document = f.nr_document
           AND ld.doc_type_xrp = f.doc_type_xrp
       JOIN mv_clienti cli           ON cli.cod_client = f.cod_client
       JOIN mv_zone z                ON z.id = cli.id_zona
       JOIN zone_agenti@lnk_distributie za
            ON za.id_zona = cli.id_zona
           AND f.data_doc_efectiva BETWEEN za.start_date
                                       AND NVL(za.end_date, DATE '9999-12-31')
       JOIN agenti@lnk_distributie a ON a.id = za.id_agent
       JOIN mv_items_core ic         ON ic.item_code = ld.item_code
       JOIN mv_items_category c      ON c.id = ic.category_id
WHERE  f.tip_doc = 'F'
  AND  f.data_doc_efectiva >= DATE '2024-01-01'
  AND  f.data_doc_efectiva <  DATE '2025-01-01'
GROUP BY a.nume_agent, z.den_zona, c.name
ORDER BY total_2024 DESC
FETCH FIRST 10 ROWS ONLY;

-- ====== 2. Plan RBO ======
PROMPT === 2. Plan RBO (HINT /*+ RULE */) ===

EXPLAIN PLAN SET STATEMENT_ID = 'Q_RBO' FOR
SELECT /*+ RULE */
       a.nume_agent, z.den_zona, c.name AS categorie,
       SUM(ld.xrp_linie_valoare_fara_tva) AS total_2024
FROM   v_fise_clienti f
       JOIN v_linii_doc ld
            ON ld.nr_document = f.nr_document
           AND ld.doc_type_xrp = f.doc_type_xrp
       JOIN mv_clienti cli           ON cli.cod_client = f.cod_client
       JOIN mv_zone z                ON z.id = cli.id_zona
       JOIN zone_agenti@lnk_distributie za
            ON za.id_zona = cli.id_zona
           AND f.data_doc_efectiva BETWEEN za.start_date
                                       AND NVL(za.end_date, DATE '9999-12-31')
       JOIN agenti@lnk_distributie a ON a.id = za.id_agent
       JOIN mv_items_core ic         ON ic.item_code = ld.item_code
       JOIN mv_items_category c      ON c.id = ic.category_id
WHERE  f.tip_doc = 'F'
  AND  f.data_doc_efectiva >= DATE '2024-01-01'
  AND  f.data_doc_efectiva <  DATE '2025-01-01'
GROUP BY a.nume_agent, z.den_zona, c.name
ORDER BY total_2024 DESC
FETCH FIRST 10 ROWS ONLY;

SELECT plan_table_output FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, 'Q_RBO', 'BASIC +ROWS +COST'));

-- ====== 3. Plan CBO default ======
PROMPT === 3. Plan CBO default ===

EXPLAIN PLAN SET STATEMENT_ID = 'Q_CBO' FOR
SELECT a.nume_agent, z.den_zona, c.name AS categorie,
       SUM(ld.xrp_linie_valoare_fara_tva) AS total_2024
FROM   v_fise_clienti f
       JOIN v_linii_doc ld
            ON ld.nr_document = f.nr_document
           AND ld.doc_type_xrp = f.doc_type_xrp
       JOIN mv_clienti cli           ON cli.cod_client = f.cod_client
       JOIN mv_zone z                ON z.id = cli.id_zona
       JOIN zone_agenti@lnk_distributie za
            ON za.id_zona = cli.id_zona
           AND f.data_doc_efectiva BETWEEN za.start_date
                                       AND NVL(za.end_date, DATE '9999-12-31')
       JOIN agenti@lnk_distributie a ON a.id = za.id_agent
       JOIN mv_items_core ic         ON ic.item_code = ld.item_code
       JOIN mv_items_category c      ON c.id = ic.category_id
WHERE  f.tip_doc = 'F'
  AND  f.data_doc_efectiva >= DATE '2024-01-01'
  AND  f.data_doc_efectiva <  DATE '2025-01-01'
GROUP BY a.nume_agent, z.den_zona, c.name
ORDER BY total_2024 DESC
FETCH FIRST 10 ROWS ONLY;

SELECT plan_table_output FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, 'Q_CBO', 'BASIC +ROWS +COST'));

-- ====== 4. Plan CBO + DRIVING_SITE in DISTRIBUTIE ======
PROMPT === 4. Plan CBO + DRIVING_SITE(a) (assembly remote) ===

EXPLAIN PLAN SET STATEMENT_ID = 'Q_DRV' FOR
SELECT /*+ DRIVING_SITE(a) */
       a.nume_agent, z.den_zona, c.name AS categorie,
       SUM(ld.xrp_linie_valoare_fara_tva) AS total_2024
FROM   v_fise_clienti f
       JOIN v_linii_doc ld
            ON ld.nr_document = f.nr_document
           AND ld.doc_type_xrp = f.doc_type_xrp
       JOIN mv_clienti cli           ON cli.cod_client = f.cod_client
       JOIN mv_zone z                ON z.id = cli.id_zona
       JOIN zone_agenti@lnk_distributie za
            ON za.id_zona = cli.id_zona
           AND f.data_doc_efectiva BETWEEN za.start_date
                                       AND NVL(za.end_date, DATE '9999-12-31')
       JOIN agenti@lnk_distributie a ON a.id = za.id_agent
       JOIN mv_items_core ic         ON ic.item_code = ld.item_code
       JOIN mv_items_category c      ON c.id = ic.category_id
WHERE  f.tip_doc = 'F'
  AND  f.data_doc_efectiva >= DATE '2024-01-01'
  AND  f.data_doc_efectiva <  DATE '2025-01-01'
GROUP BY a.nume_agent, z.den_zona, c.name
ORDER BY total_2024 DESC
FETCH FIRST 10 ROWS ONLY;

SELECT plan_table_output FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, 'Q_DRV', 'BASIC +ROWS +COST'));
```

- [ ] **Step 2: Run and save output**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_vanzari/oracle@localhost:1521/VANZARI < /Users/octav/MODBD/modbd/oracle/ddl/30_query_complex.sql > /tmp/q_complex_output.txt 2>&1
cat /tmp/q_complex_output.txt | head -200
```
Expected: 4 sections of output. First section shows up to 10 rows (data results). Sections 2-4 show plan trees with COST column populated.

- [ ] **Step 3: Compare costs**

```bash
grep -E "Plan hash|Cost|^---" /tmp/q_complex_output.txt | head -30
```
Inspect: cost-ul total ar trebui să difere între RBO (mai mare, fără statistici) și CBO (mai mic, optimizat). DRIVING_SITE poate fi mai bun sau mai prost depinzând de date.

- [ ] **Step 4: Save output for raport**

```bash
cp /tmp/q_complex_output.txt /Users/octav/MODBD/modbd/oracle/ddl/30_query_complex_output.txt
```

- [ ] **Step 5: Commit**

```bash
cd /Users/octav/MODBD && \
  git add modbd/oracle/ddl/30_query_complex.sql modbd/oracle/ddl/30_query_complex_output.txt && \
  git commit -m "feat: complex query (top 10 agents 2024) + 3-way EXPLAIN PLAN (RBO/CBO/DRIVING_SITE)"
```

---

## Task 17: End-to-end validation

**Files:**
- Create: `modbd/oracle/ddl/40_validare_end_to_end.sql`

- [ ] **Step 1: Write the validation script**

Create `/Users/octav/MODBD/modbd/oracle/ddl/40_validare_end_to_end.sql`:
```sql
-- =============================================================================
-- 40_validare_end_to_end.sql
-- Verifica toate componentele BD-ului distribuit end-to-end:
--   1. Counts pe toate tabelele (PDB-uri) + MV-uri replicate
--   2. View-uri de transparenta returneaza acelasi total ca fragmentele
--   3. INSTEAD OF triggers functioneaza pe V_FISE (INSERT/UPDATE/DELETE)
--   4. FK cross-PDB blocheaza inserari invalide
--   5. Sync MV functioneaza dupa refresh manual
-- =============================================================================

SET SERVEROUTPUT ON
SET LINESIZE 200

-- Test 1: Counts
PROMPT === Test 1: Counts globale ===
SELECT 'distributie.clienti' AS t, COUNT(*) AS n FROM clienti@lnk_distributie
UNION ALL SELECT 'distributie.zone', COUNT(*) FROM zone@lnk_distributie
UNION ALL SELECT 'catalog.items_core', COUNT(*) FROM items_core@lnk_catalog
UNION ALL SELECT 'vanzari.v_fise', COUNT(*) FROM v_fise_clienti
UNION ALL SELECT 'vanzari.v_linii', COUNT(*) FROM v_linii_doc
UNION ALL SELECT 'vanzari.mv_clienti', COUNT(*) FROM mv_clienti
UNION ALL SELECT 'vanzari.mv_items_core', COUNT(*) FROM mv_items_core;

-- Test 2: Transparenta UNION ALL
PROMPT === Test 2: View total = sum fragments ===
SELECT (SELECT COUNT(*) FROM v_fise_clienti)
       - ((SELECT COUNT(*) FROM fise_clienti_ro) + (SELECT COUNT(*) FROM fise_clienti_ext))
       AS diff_fise FROM dual;

-- Test 3: INSERT prin view -> aterizeaza pe fragmentul corect
PROMPT === Test 3: INSTEAD OF INSERT pe V_FISE ===
INSERT INTO v_fise_clienti VALUES (
  77777777, 'TEST_RO', NULL, 'F', 'INV', SYSDATE, NULL,
  1, 'RON', 100, 100, NULL, 'CLI000001', 'Alpha Distrib SRL', 'DISTR'
);
INSERT INTO v_fise_clienti VALUES (
  77777778, 'TEST_EUR', NULL, 'F', 'INV', SYSDATE, NULL,
  1, 'EUR', 50, 250, NULL, 'CLI000001', 'Alpha Distrib SRL', 'DISTR'
);
SELECT COUNT(*) AS in_ro FROM fise_clienti_ro WHERE id = 77777777;    -- expect 1
SELECT COUNT(*) AS in_ext FROM fise_clienti_ext WHERE id = 77777778;  -- expect 1
ROLLBACK;

-- Test 4: FK cross-PDB blocheaza
PROMPT === Test 4: FK cross-PDB rejects bad client ===
DECLARE
  v_failed BOOLEAN := FALSE;
BEGIN
  BEGIN
    INSERT INTO fise_clienti_ro (id, nr_document, tip_doc, doc_type_xrp,
      data_doc_efectiva, semn, moneda, amount_doc, amount_doc_ron,
      cod_client, denumire_client, clasa_client)
    VALUES (88888888, 'BAD_FK', 'F', 'INV', SYSDATE, 1, 'RON', 100, 100,
            'NONEXISTENT', 'Test', 'DISTR');
  EXCEPTION
    WHEN OTHERS THEN
      v_failed := TRUE;
      DBMS_OUTPUT.PUT_LINE('FK OK: ' || SQLERRM);
  END;
  IF NOT v_failed THEN
    DBMS_OUTPUT.PUT_LINE('FAILED: insertul nu a fost respins!');
    ROLLBACK;
  END IF;
END;
/

-- Test 5: Sync MV (forced refresh)
PROMPT === Test 5: Manual refresh MV ===
EXEC DBMS_MVIEW.REFRESH('MV_CLIENTI', method=>'F');
SELECT COUNT(*) AS mv_clienti_count FROM mv_clienti;
```

- [ ] **Step 2: Run**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_vanzari/oracle@localhost:1521/VANZARI < /Users/octav/MODBD/modbd/oracle/ddl/40_validare_end_to_end.sql
```
Expected output sections:
- Test 1: 7 counts, all non-zero, mv_clienti=10, mv_items_core=3192
- Test 2: `DIFF_FISE` = `0`
- Test 3: both `IN_RO`=1 and `IN_EXT`=1, rollback at end
- Test 4: prints `FK OK: ORA-02291: integrity constraint ...`
- Test 5: prints count after refresh

- [ ] **Step 3: Take a screenshot or save output for raport**

```bash
docker exec -i oracle-modbd sqlplus -s sgbd_vanzari/oracle@localhost:1521/VANZARI < /Users/octav/MODBD/modbd/oracle/ddl/40_validare_end_to_end.sql > /Users/octav/MODBD/modbd/oracle/ddl/40_validare_output.txt 2>&1
```

- [ ] **Step 4: Commit**

```bash
cd /Users/octav/MODBD && \
  git add modbd/oracle/ddl/40_validare_end_to_end.sql modbd/oracle/ddl/40_validare_output.txt && \
  git commit -m "test: end-to-end validation (counts, transparency, FK, sync)"
```

- [ ] **Step 5: Final commit cu summary**

```bash
cd /Users/octav/MODBD && git log --oneline
```
Expected: ~17 commits (each task + initial). Review history.

---

## Notes for the implementer

- **Order matters**: Tasks 1-17 must be run in sequence. Task 12 depends on Tasks 10-11 being complete.
- **Idempotency**: Most DDL scripts use `CREATE OR REPLACE` for views/triggers, but `CREATE TABLE` is not idempotent. If you need to re-run a DDL script, manually drop tables first or modify the script.
- **Connection patterns**: SYS-as-sysdba to CDB for cross-PDB operations (Tasks 2, 10). App users for PDB-local DDL.
- **Performance**: ITEMS table has 3192 rows. The CSV-derived BEA scenario assumes B2B distribution. Performance should be sub-second for all queries.
- **Containers**: Container `oracle-modbd` must be running. If stopped: `docker start oracle-modbd` + wait 30s for ready state.
- **Debugging**: If an external table fails to load, check `SELECT * FROM USER_LOAD_LOG;` or look in container logs at `/opt/oracle/diag/rdbms/...`.

---

## Self-review checklist

This plan covers all spec sections:

| Spec section | Plan task(s) |
|---|---|
| 2.1 Container Oracle | (existing, Task 1 commits state) |
| 2.2 PDB structure | (existing, Task 1 commits state) |
| 2.3 Role + utilizatori | (existing, Task 1 commits state) |
| 3 Architecture | Task 11 (DB links) |
| 4.1 Schema DISTRIBUTIE | Task 3 |
| 4.2 Schema CATALOG | Task 5 |
| 4.3.1 Fragmente VANZARI | Task 7 |
| 4.3.2 Views UNION ALL | Task 9 |
| 4.3.3 MVs replicate | Task 12 |
| 4.3.4 Cross-PDB FKs | Task 12 |
| 5 Fragmentari (BEA + horizontal) | Task 6 (split ITEMS), Task 8 (split FISE/LINII) |
| 6.1 MV logs | Task 10 |
| 6.2 MVs FAST refresh | Task 12 |
| 6.3 Scheduler job | Task 13 |
| 7.1 CHECK constraints | Tasks 3, 5, 7 (inline in DDL) |
| 7.2 FK locale | Tasks 3, 5, 7 + 12 (cross-PDB) |
| 7.3 Aggregate trigger | Task 14 |
| 7.4 INSTEAD OF triggers | Tasks 5 (V_ITEMS), 9 (V_FISE, V_LINII) |
| 8 Complex query + RBO/CBO | Tasks 15 (indexes/stats), 16 (3 EXPLAIN PLAN) |
| 10 Riscuri | Task 14 (note about historical data) |
