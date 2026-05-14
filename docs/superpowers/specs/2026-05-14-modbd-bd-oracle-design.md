# Design BD Oracle distribuit — proiect MODBD (modul 2)

**Autor**: Octavian Oprinoiu
**Materie**: Metode de Optimizare și Distribuire în Baze de Date (MODBD), FMI Universitatea București, 2025–2026
**Data**: 2026-05-14
**Scope**: Modulul 2 (Implementare BD Oracle, 10p). Modulele 1 (Analiză) și 3 (Aplicație front-end) primesc spec-uri separate.

---

## 1. Context

### 1.1. Sursa datelor

Datele provin dintr-o BD SQL Server numită `Integration`, sub-domeniu **distribuție B2B fashion** (încălțăminte, articole vestimentare; zone comerciale RO + CZ + SK). Subset-ul selectat (vezi `MODBD_HANDOFF.md`, secțiunea 6):

- 10 clienți anonimizați (`CLI000001`..`CLI000010`)
- 5 zone (ARDEAL, MOLDOVA, SUD, SLOVACIA, CEHIA) — 3 interne + 2 externe
- 6 agenți (`AG001`..`AG006`)
- 2.048 documente (`FISE_CLIENTI`) acoperind 2021–2026 (~66 luni)
- 5.598 linii document (`LINII_DOC`)
- 3.192 produse (`ITEMS`) + 131 branduri + 15 categorii + 3 tipuri + 17 sezoane

### 1.2. Cerințe baremul oficial (Modulul 2, 10p)

| Punctaj | Cerință | Obligatoriu |
|---|---|---|
| 0.5p | Creare BD-uri + utilizatori | da |
| 1p | Creare relații + fragmente | da |
| 0.5p | Populare cu date | da |
| 2.5p | Transparență (1p vertical + 1p orizontal + 0.5p tabele în alte BD-uri) | nu |
| 1p | Sincronizare relații replicate | nu |
| 2p | Toate constrângerile (locale + globale) | da |
| 1.5p | Optimizare cerere SQL (RBO + CBO + sugestii) | nu |

Obligatoriu = 4p; total maxim = 9p (rest 1p e implicit alocat detaliilor de execuție / discrepanță cu baremul detaliat — vezi PDF original).

### 1.3. Aliniere cu cursul

Sursa: PDF `ilovepdf_merged.pdf` (205 pagini), curs predat de Lect. dr. Gabriela Mihai + Andrei Alexandru Neagu (Specialist Industrie).

Capitole referențiate explicit:
- **Cap. 2.3.1** — Fragmentare orizontală primară (predicate simple/compuse + selecție)
- **Cap. 2.3.2** — Fragmentare orizontală derivată (semijoin)
- **Cap. 2.4** — Fragmentare verticală (algoritm BEA: VA → AA → LEG_AFIN → PART)
- **Cap. 3.2.2** — Vizualizări în sisteme distribuite (vizualizări materializate)
- **Cap. 3.4** — Control integritate semantică (3 clase de propoziții)
- **Cap. 5** — Optimizare cereri distribuite (Ingres / System R / System R* / SDD-1)

Convenția de instalare urmează **Anexa ARM** din curs (final, paginile 184–205) — adaptată: am folosit Oracle 21c XE în loc de 19c EE (vezi 2.1).

---

## 2. Infrastructură (deja realizată)

### 2.1. Container Oracle

| Aspect | Configurație |
|---|---|
| Imagine | `gvenzl/oracle-xe:21-slim-faststart` (linux/amd64 sub Rosetta pe Mac M4) |
| Container | `oracle-modbd` (port 1521 expus) |
| Volume CSV | `/Users/octav/MODBD/modbd` → `/csv:ro` (read-only mount) |
| Volume datafile | `oracle-modbd-data` → `/opt/oracle/oradata` (persistent) |
| Parolă SYS/SYSTEM | `ModbdSecret123` *(curs sugerează `Admin#DB1`; păstrăm valoarea noastră — nu impune)* |

> **Diferență față de curs**: cursul cere Oracle 19c Enterprise Edition build manual din `oracle/docker-images` + LINUX.ARM64 zip oficial. Am preferat 21c XE community pentru viteză de setup. Diferențele tehnice pentru proiect sunt minime (DDL identic, MV-uri identice, partition-by-list identic). Dacă apare orice incompatibilitate, migrare la 19c EE înainte de predare conform Anexa cursului.

### 2.2. Structura PDB-urilor

CDB rădăcină: `XE` (SID).

Cele 3 BD-uri locale = 3 PDB-uri (XE 21c suportă maxim 3 user PDBs):

| PDB | Datafile path | User schema | Parolă |
|---|---|---|---|
| `DISTRIBUTIE` | `/opt/oracle/oradata/XE/distributie/` | `SGBD_DISTRIBUTIE` | `oracle` |
| `CATALOG` | `/opt/oracle/oradata/XE/catalog/` | `SGBD_CATALOG` | `oracle` |
| `VANZARI` | `/opt/oracle/oradata/XE/vanzari/` | `SGBD_VANZARI` | `oracle` |

Toate 3 sunt READ WRITE + auto-open la restart (`SAVE STATE`). Tablespace `USERS` creat în fiecare cu datafile dedicat (100M, autoextend până la 2G).

### 2.3. Role + utilizatori (convenția cursului)

În fiecare PDB există role-ul `sgbd_role` cu următoarele grant-uri (din ghidul de instalare al cursului, pagina 17):

```sql
GRANT connect, resource TO sgbd_role;
GRANT create table, create view, create materialized view TO sgbd_role;
GRANT create synonym, create procedure, create sequence TO sgbd_role;
GRANT create trigger, create type TO sgbd_role;
GRANT query rewrite, select_catalog_role, alter session TO sgbd_role;
GRANT select any dictionary TO sgbd_role;
GRANT create database link, create public database link TO sgbd_role;
GRANT create public synonym TO sgbd_role;
```

Utilizatorul aplicativ în fiecare PDB:
```sql
CREATE USER sgbd_<pdbname> IDENTIFIED BY oracle
  DEFAULT TABLESPACE users
  QUOTA UNLIMITED ON users;
GRANT sgbd_role TO sgbd_<pdbname>;
GRANT unlimited tablespace TO sgbd_<pdbname>;
```

---

## 3. Arhitectura distribuției

### 3.1. Diagramă logică

```
                        CDB$ROOT (XE)
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
   ┌──────────┐         ┌──────────┐         ┌──────────┐
   │DISTRIBUTIE│         │ CATALOG  │         │ VANZARI  │
   └──────────┘         └──────────┘         └──────────┘
   ZONE                 BRANDS               FISE_CLIENTI_RO
   AGENTI               ITEMS_CATEGORY       FISE_CLIENTI_EXT
   CLIENTI              ITEMS_TYPE           LINII_DOC_RO
   CLIENTI_CONTACTE     ITEMS_SEASONS        LINII_DOC_EXT
   INTERVALE_PLATA      ITEMS_CORE  ─┐       V_FISE_CLIENTI  (view UNION)
   INTERVALE_PLATA_ZILE ITEMS_EXTRA  │       V_LINII_DOC     (view UNION)
   ZONE_AGENTI          V_ITEMS  ←───┘
   ZONE_INTERVALE_PLATA                      MV_CLIENTI       ← lnk_distributie
                                             MV_ZONE
                                             MV_ITEMS_CORE    ← lnk_catalog
                                             MV_BRANDS
                                             MV_ITEMS_CATEGORY
                                             MV_ITEMS_TYPE
                                             MV_ITEMS_SEASONS
```

### 3.2. Justificare distribuție per nod

- **DISTRIBUTIE = CRM/Comercial** (8 tabele master, volume mici, frecvent referențiate ca dimensiune). Single-master pentru clienți, agenți, zone, intervale de plată. Conține și cele 2 din 3 relații M:N (`ZONE_AGENTI`, `ZONE_INTERVALE_PLATA`).
- **CATALOG = Produse** (4 lookup + 1 entitate mare cu fragmentare verticală). Self-contained — fragmentele `ITEMS_CORE`/`ITEMS_EXTRA` rezidă local și se expun unificat prin `V_ITEMS`.
- **VANZARI = Tranzacții + raportare** (fact tables fragmentate orizontal, plus toate replicile pentru raportare locală fără hop-uri remote pentru join-uri pe dimensiuni mici).

### 3.3. Direcția DB links

Doar VANZARI inițiază link-uri (e nodul "consumer" în topologia stea):

```sql
-- În SGBD_VANZARI@VANZARI
CREATE DATABASE LINK lnk_distributie
  CONNECT TO sgbd_distributie IDENTIFIED BY oracle
  USING 'localhost:1521/DISTRIBUTIE';

CREATE DATABASE LINK lnk_catalog
  CONNECT TO sgbd_catalog IDENTIFIED BY oracle
  USING 'localhost:1521/CATALOG';
```

Test smoke: `SELECT COUNT(*) FROM clienti@lnk_distributie;`

---

## 4. Schema detaliată

### 4.1. PDB DISTRIBUTIE (schema `SGBD_DISTRIBUTIE`)

```sql
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

CREATE TABLE zone_agenti (  -- M:N #1
  id          NUMBER(19) PRIMARY KEY,
  id_zona     NUMBER(19) NOT NULL,
  id_agent    NUMBER(19) NOT NULL,
  start_date  DATE       NOT NULL,
  end_date    DATE,
  CONSTRAINT fk_za_zona FOREIGN KEY (id_zona) REFERENCES zone(id),
  CONSTRAINT fk_za_agent FOREIGN KEY (id_agent) REFERENCES agenti(id),
  CONSTRAINT ck_za_dates CHECK (end_date IS NULL OR end_date > start_date)
);

CREATE TABLE zone_intervale_plata (  -- M:N #2
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

### 4.2. PDB CATALOG (schema `SGBD_CATALOG`)

```sql
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
  season_year  VARCHAR2(8),     -- redenumit din 'year' (cuvânt rezervat în Oracle)
  active       NUMBER(10),
  CONSTRAINT uk_seasons_code UNIQUE (code),
  CONSTRAINT ck_seasons_active CHECK (active IN (0,1))
);

-- Fragmentul vertical 1 (CORE): atribute identificare + clasificare (cca 8 col)
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

-- Fragmentul vertical 2 (EXTRA): atribute comerciale + fizice (cca 7 col + id)
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

-- View de transparență verticală
CREATE OR REPLACE VIEW v_items AS
SELECT c.id, c.item_code, c.item_name, e.item_description,
       c.brand_id, c.season_id, c.item_type_id, c.category_id,
       e.vat, e.last_cost_price, e.main_barcode, e.supplier_code,
       e.weight, e.um, c.active
FROM   items_core c
       JOIN items_extra e ON e.id = c.id;
```

### 4.3. PDB VANZARI (schema `SGBD_VANZARI`)

#### 4.3.1. Fragmente fizice

```sql
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

-- Fragment H primar 2: moneda ≠ 'RON' (EUR, CZK, USD)
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

-- Fragment H derivat 1
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

-- Fragment H derivat 2
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

#### 4.3.2. View-uri de transparență (UNION ALL)

```sql
CREATE OR REPLACE VIEW v_fise_clienti AS
SELECT * FROM fise_clienti_ro
UNION ALL
SELECT * FROM fise_clienti_ext;

CREATE OR REPLACE VIEW v_linii_doc AS
SELECT * FROM linii_doc_ro
UNION ALL
SELECT * FROM linii_doc_ext;
```

#### 4.3.3. Materialized Views replicate

```sql
-- Replici din DISTRIBUTIE
CREATE MATERIALIZED VIEW mv_clienti
  REFRESH FAST ON DEMAND
  WITH PRIMARY KEY
  AS SELECT * FROM clienti@lnk_distributie;

CREATE MATERIALIZED VIEW mv_zone
  REFRESH FAST ON DEMAND
  WITH PRIMARY KEY
  AS SELECT * FROM zone@lnk_distributie;

-- Replici din CATALOG
CREATE MATERIALIZED VIEW mv_items_core
  REFRESH FAST ON DEMAND
  WITH PRIMARY KEY
  AS SELECT * FROM items_core@lnk_catalog;

CREATE MATERIALIZED VIEW mv_brands
  REFRESH FAST ON DEMAND
  WITH PRIMARY KEY
  AS SELECT * FROM brands@lnk_catalog;

CREATE MATERIALIZED VIEW mv_items_category
  REFRESH FAST ON DEMAND
  WITH PRIMARY KEY
  AS SELECT * FROM items_category@lnk_catalog;

CREATE MATERIALIZED VIEW mv_items_type
  REFRESH FAST ON DEMAND
  WITH PRIMARY KEY
  AS SELECT * FROM items_type@lnk_catalog;

CREATE MATERIALIZED VIEW mv_items_seasons
  REFRESH FAST ON DEMAND
  WITH PRIMARY KEY
  AS SELECT * FROM items_seasons@lnk_catalog;
```

#### 4.3.4. FK-uri cross-PDB (după ce MV-urile sunt populate)

```sql
ALTER TABLE fise_clienti_ro
  ADD CONSTRAINT fk_fise_ro_client FOREIGN KEY (cod_client) REFERENCES mv_clienti(cod_client);
ALTER TABLE fise_clienti_ext
  ADD CONSTRAINT fk_fise_ext_client FOREIGN KEY (cod_client) REFERENCES mv_clienti(cod_client);

ALTER TABLE linii_doc_ro
  ADD CONSTRAINT fk_lin_ro_item FOREIGN KEY (item_code) REFERENCES mv_items_core(item_code);
ALTER TABLE linii_doc_ext
  ADD CONSTRAINT fk_lin_ext_item FOREIGN KEY (item_code) REFERENCES mv_items_core(item_code);
```

---

## 5. Fragmentări — justificare academică

### 5.1. Fragmentare verticală pe `ITEMS` (algoritm BEA, curs cap. 2.4)

#### 5.1.1. Workload proiectat

Frecvențele `acc(qi)` sunt derivate din volumul efectiv din CSV (perioada 2021–2026 ≈ 66 luni, 5.598 linii document, 3.192 produse) și completate cu coeficienți de scalare bazați pe profilul tipic de distribuție B2B:

| Cod | Aplicație | Derivare | `acc/lună` |
|---|---|---|---|
| q1 | Catalog browse | 6 agenți × 4 sesiuni/lună | 25 |
| q2 | Insert linie factură | 5.598 / 66 luni | 85 |
| q3 | Raport top vânzări (manageriat) | rulare lunară | 1 |
| q4 | Editare fișă produs (admin) | 3.192 × 10% revizuiri/an / 12 | 25 |
| q5 | Update cost & furnizor (per produs) | 3.192 × 12% ciclu/an / 12 | 30 |

#### 5.1.2. Matricea de utilizare VA

Coloane non-PK (PK `id` e replicat în ambele fragmente, deci nu intră în BEA):

|     | item_code | item_name | item_desc | brand | season | type | cat | active | vat | cost | barcode | supplier | weight | um |
|-----|-----------|-----------|-----------|-------|--------|------|-----|--------|-----|------|---------|----------|--------|----|
| q1  | 1 | 1 | 0 | 1 | 1 | 1 | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| q2  | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| q3  | 1 | 1 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| q4  | 0 | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 1 | 0 | 1 | 1 |
| q5  | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 1 | 0 | 0 |

#### 5.1.3. Calculul afinităților + LEG_AFIN + PART

Aplicând formula `aff(Ai, Aj) = Σ_{q | use(q,Ai)=use(q,Aj)=1} acc(q)`, după permutările LEG_AFIN matricea CA grupează:

- **Cluster CORE**: `item_code, item_name, brand_id, season_id, item_type_id, category_id, active` (afinitate ridicată cu q1+q2+q3)
- **Cluster EXTRA**: `item_description, vat, last_cost_price, main_barcode, supplier_code, weight, um` (afinitate cu q4+q5)

Algoritmul PART caută punctul `x` care maximizează `z = CTQ·CBQ − COQ²`:

- `TQ = {q1, q2, q3}` (CORE only) → `CTQ = 25 + 85 + 1 = 111`
- `BQ = {q5}` (EXTRA only) → `CBQ = 30`
- `OQ = {q4}` (cross-cluster) → `COQ = 25`
- `z = 111 × 30 − 25² = 3.330 − 625 = 2.705` *(maximum global)*

#### 5.1.4. Verificare corectitudine (curs 2.4)

- *Completitudine*: ITEMS_CORE ∪ ITEMS_EXTRA acoperă toate cele 15 atribute originale. ✓
- *Reconstrucție*: `ITEMS = ITEMS_CORE ⋈_id ITEMS_EXTRA` (join pe PK). ✓
- *Disjuncție*: singurul atribut comun e `id` (PK); restul disjuncte. ✓

### 5.2. Fragmentare orizontală primară pe `FISE_CLIENTI` (curs cap. 2.3.1)

#### 5.2.1. Predicate

Predicate simple `Pr`:
- `p1: moneda = 'RON'`
- `p2: moneda = 'EUR'`
- `p3: moneda = 'CZK'`

Predicate compuse minimale și complete `M` (simplificate la 2 fragmente prin gruparea EUR+CZK):
- `m1: moneda = 'RON'`
- `m2: moneda ≠ 'RON'`

#### 5.2.2. Definire fragmente prin selecție

```
FISE_CLIENTI_RO  = σ(moneda='RON')   (FISE_CLIENTI)
FISE_CLIENTI_EXT = σ(moneda<>'RON')  (FISE_CLIENTI)
```

#### 5.2.3. Verificare corectitudine

- *Completitudine*: m1 ∨ m2 ≡ TRUE pentru orice tuplu cu `moneda` non-null. ✓
- *Reconstrucție*: `FISE_CLIENTI = FISE_CLIENTI_RO ∪ FISE_CLIENTI_EXT`. ✓
- *Disjuncție*: m1 ∧ m2 ≡ FALSE. ✓

### 5.3. Fragmentare orizontală derivată pe `LINII_DOC` (curs cap. 2.3.2)

Legătura L între `FISE_CLIENTI` (owner) și `LINII_DOC` (member) prin cheia compusă `(nr_document, doc_type_xrp)`:

```
LINII_DOC_RO  = LINII_DOC ⋉ FISE_CLIENTI_RO    (semijoin)
LINII_DOC_EXT = LINII_DOC ⋉ FISE_CLIENTI_EXT
```

Graf simplu (fiecare linie are exact un header) ⇒ disjuncție automat asigurată.

#### Verificare corectitudine

- *Completitudine*: integritatea referențială asigură fiecare linie cu header. ✓
- *Reconstrucție*: `LINII_DOC = LINII_DOC_RO ∪ LINII_DOC_EXT`. ✓
- *Disjuncție*: cheia unică ⇒ o linie într-un singur fragment. ✓

---

## 6. Strategia de replicare

### 6.1. MV logs pe master (DISTRIBUTIE + CATALOG)

```sql
-- În SGBD_DISTRIBUTIE@DISTRIBUTIE
CREATE MATERIALIZED VIEW LOG ON clienti WITH PRIMARY KEY, ROWID, SEQUENCE INCLUDING NEW VALUES;
CREATE MATERIALIZED VIEW LOG ON zone    WITH PRIMARY KEY, ROWID, SEQUENCE INCLUDING NEW VALUES;

-- În SGBD_CATALOG@CATALOG
CREATE MATERIALIZED VIEW LOG ON items_core      WITH PRIMARY KEY, ROWID, SEQUENCE INCLUDING NEW VALUES;
CREATE MATERIALIZED VIEW LOG ON brands          WITH PRIMARY KEY, ROWID, SEQUENCE INCLUDING NEW VALUES;
CREATE MATERIALIZED VIEW LOG ON items_category  WITH PRIMARY KEY, ROWID, SEQUENCE INCLUDING NEW VALUES;
CREATE MATERIALIZED VIEW LOG ON items_type      WITH PRIMARY KEY, ROWID, SEQUENCE INCLUDING NEW VALUES;
CREATE MATERIALIZED VIEW LOG ON items_seasons   WITH PRIMARY KEY, ROWID, SEQUENCE INCLUDING NEW VALUES;
```

### 6.2. MV-uri în VANZARI (vezi 4.3.3)

Toate cu `REFRESH FAST ON DEMAND WITH PRIMARY KEY`. *Restricția Oracle*: `REFRESH ON COMMIT` nu e disponibil cross-PDB; obligatoriu ON DEMAND + job programat.

### 6.3. Job scheduler (sync 60s)

```sql
-- În SGBD_VANZARI@VANZARI
BEGIN
  DBMS_SCHEDULER.CREATE_JOB(
    job_name        => 'JOB_REFRESH_MVS',
    job_type        => 'PLSQL_BLOCK',
    job_action      => q'[BEGIN
      DBMS_MVIEW.REFRESH(
        'MV_CLIENTI,MV_ZONE,MV_ITEMS_CORE,MV_BRANDS,MV_ITEMS_CATEGORY,MV_ITEMS_TYPE,MV_ITEMS_SEASONS',
        method => 'FFFFFFF');
    END;]',
    repeat_interval => 'FREQ=SECONDLY;INTERVAL=60',
    enabled         => TRUE);
END;
/
```

### 6.4. Trade-off acceptat

- Lag de până la 60s între master și MV; insertul într-un master + insert imediat dependent în VANZARI poate eșua tranzitoriu.
- Pentru demo: rulăm `EXEC DBMS_MVIEW.REFRESH(...);` manual înainte de query-urile dependente.
- Pentru producție: refresh group cu commit propagation (în afara scope-ului proiectului).

---

## 7. Constrângeri — controlul integrității semantice (curs cap. 3.4)

### 7.1. Clasa 1 — Propoziții individuale

| Tip | Localizare | Exemple |
|---|---|---|
| NOT NULL | toate PDB-urile | PK-uri, `cod_client`, `nr_document`, `moneda`, `item_code` |
| CHECK domain | toate | `tip_doc IN ('F','I')`, `doc_type_xrp IN (...)`, `semn IN (-1,1)`, `active IN (0,1)` |
| CHECK fragment (predicat fragmentare) | VANZARI | `ck_fise_ro_mon: moneda='RON'`, `ck_fise_ext_mon: moneda<>'RON'` |
| CHECK temporal | DISTRIBUTIE | `end_date IS NULL OR end_date > start_date` pe clienti, zone_agenti, zone_intervale_plata |

### 7.2. Clasa 2 — Propoziții orientate pe mulțime

**FK locale** (intra-PDB) — vezi 4.1, 4.2, 4.3.1.

**FK globale** (cross-PDB via MV) — vezi 4.3.4:
- `fise_clienti_*.cod_client → mv_clienti.cod_client`
- `linii_doc_*.item_code → mv_items_core.item_code`

Conform curs 3.4.2 (cazul "fragmentare prin semijoin cu owner replicat"): verificarea compatibilității e ieftină pentru că tuplul owner replicat e local.

### 7.3. Clasa 3 — Propoziții cu agregate

**Coerența sum-document ↔ sum-linii** (trigger AFTER STATEMENT pe `linii_doc_*`):

```sql
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
    RAISE_APPLICATION_ERROR(-20001, 'Incoerență sumă pe ' || r.nr_document || '/' || r.doc_type_xrp);
  END LOOP;
END;
/
```

### 7.4. Triggere INSTEAD OF (transparență DML)

Pentru ca view-urile UNION ALL / JOIN să fie updatable conform cerinței de transparență (2.5p):

```sql
-- Helper local: ordinea canonică a celor 15 coloane folosite în toate VALUES-urile
-- (id, nr_document, nr_doc_initial, tip_doc, doc_type_xrp, data_doc_efectiva,
--  data_scad, semn, moneda, amount_doc, amount_doc_ron, plata_prin,
--  cod_client, denumire_client, clasa_client)

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
  -- Mutare cross-fragment dacă moneda se schimbă din RON ↔ non-RON
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

-- INSTEAD OF DELETE: rutează după ID
CREATE OR REPLACE TRIGGER trg_v_fise_del
INSTEAD OF DELETE ON v_fise_clienti
FOR EACH ROW
BEGIN
  DELETE FROM fise_clienti_ro  WHERE id = :OLD.id;
  DELETE FROM fise_clienti_ext WHERE id = :OLD.id;
END;
/
```

Triggere similare pentru `v_linii_doc` (rutare după FK către fragmentele de FISE) și `v_items` (split INSERT în CORE + EXTRA).

---

## 8. Cererea SQL complexă + optimizare (curs cap. 5)

### 8.1. Enunț

**Top 10 agenți după valoarea totală vândută în 2024**, defalcată pe zonă comercială și categorie de produs (doar facturi `tip_doc='F'`).

### 8.2. SQL

```sql
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
```

### 8.3. Mapare curs → Oracle

| Concept curs (cap. 5) | Echivalent Oracle | Tehnică demo |
|---|---|---|
| Ingres (heuristic, decomposition) | RBO | HINT `/*+ RULE */` + EXPLAIN PLAN |
| System R (CBO, dynamic programming) | CBO default | DBMS_STATS.GATHER_TABLE_STATS |
| System R* (CBO distribuit) | CBO + remote stats | DBMS_STATS.GATHER_SYSTEM_STATS |
| SDD-1 (semijoin-based) | DRIVING_SITE + semijoin hints | HINT `/*+ DRIVING_SITE */` |
| Reducerea spațiului prin euristici (5.1) | Predicat pushdown automatic | EXPLAIN PLAN arată Filter ops |
| Ordonare crescătoare a relațiilor binare (5.1.2) | Join order optimization | HINT `/*+ ORDERED */` |

### 8.4. Etape de demonstrare în raport

**Etapa 0 — Setup indecși + statistici**:
```sql
CREATE INDEX idx_fise_ro_data ON fise_clienti_ro(data_doc_efectiva);
CREATE INDEX idx_fise_ro_codcli ON fise_clienti_ro(cod_client);
CREATE INDEX idx_fise_ro_tip ON fise_clienti_ro(tip_doc);
CREATE INDEX idx_lin_ro_doc ON linii_doc_ro(nr_document, doc_type_xrp);
CREATE INDEX idx_lin_ro_item ON linii_doc_ro(item_code);
-- idem pentru fise_clienti_ext, linii_doc_ext
EXEC DBMS_STATS.GATHER_SCHEMA_STATS('SGBD_VANZARI');
```

**Etapa 1 — Plan RBO baseline**:
```sql
EXPLAIN PLAN SET STATEMENT_ID='Q_RBO' FOR
  SELECT /*+ RULE */ ... [query] ...;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, 'Q_RBO', 'BASIC +ROWS +COST'));
```

**Etapa 2 — Plan CBO default**: același query fără hint.

**Etapa 3 — Plan CBO + DRIVING_SITE**:
```sql
SELECT /*+ DRIVING_SITE(a) */ ... [query] ...;
```
Forțează assembly în DISTRIBUTIE → analizăm cost-ul de a face pull-out din VANZARI.

**Etapa 4 — Tabelă comparativă** (3 planuri × {cost estimat, num joins, num remote operations, rows scanned}) + concluzie.

### 8.5. Tehnici suplimentare (de menționat)

- **Partition pruning natural**: predicate `f.moneda = 'RON'` → scanare doar `fise_clienti_ro`
- **MV query rewrite**: dacă creăm `mv_top_2024 ... ENABLE QUERY REWRITE`, CBO poate înlocui automat query-ul cu citire din MV
- **Semijoin** (curs 5.3.2): CBO poate alege internal semijoin pentru `agenti@lnk_distributie` (relație mică, folosită doar pentru filtrare)

---

## 9. Ordinea de execuție

Pașii concreți de implementare (vor fi expandați în plan de execuție prin `superpowers:writing-plans`):

1. **DDL DISTRIBUTIE** — creare cele 8 tabele + constrângeri locale
2. **DDL CATALOG** — creare cele 4 lookup + ITEMS_CORE + ITEMS_EXTRA + V_ITEMS
3. **DDL VANZARI** — creare 4 fragmente fizice + 2 view-uri UNION ALL
4. **SQL*Loader** — încărcare CSV-uri în tabelele master (split: ITEMS → CORE/EXTRA, FISE → RO/EXT, LINII → RO/EXT)
5. **DB links VANZARI → DISTRIBUTIE, CATALOG** + smoke test
6. **MV logs** pe master + **MV-uri replicate** în VANZARI
7. **FK-uri cross-PDB** locale către MV-uri
8. **DBMS_SCHEDULER job** pentru refresh 60s
9. **Triggere INSTEAD OF** pe view-urile UNION/JOIN + **trigger agregat** pentru coerență sume
10. **Indecși + statistici** pe fact tables
11. **Query complex** + EXPLAIN PLAN RBO/CBO/DRIVING_SITE + tabelă comparativă
12. **Validare end-to-end** — query-uri prin view-urile de transparență, insert prin view, verificare FK cross-PDB

---

## 10. Riscuri identificate + mitigare

| Risc | Mitigare |
|---|---|
| `REFRESH ON COMMIT` nu funcționează cross-PDB | Acceptat lag 60s via job DBMS_SCHEDULER; pentru demo, refresh manual înainte de teste |
| Diferențe 21c XE ↔ 19c EE | DDL identic pentru toate feature-urile folosite; eventual migrare la 19c înainte de predare |
| CSV cu `NULL` ca string | SQL*Loader cu `NULLIF col='NULL'` |
| CSV cu BOM UTF-8 | Charset PDB e AL32UTF8; SQL*Loader cu `CHARACTERSET UTF8` ignoră BOM-ul de la început |
| ID-uri mari în CSV (până la `NUMBER(19)`) | Tip column `NUMBER(19)`, nu folosim `INTEGER` (limitat la 38 digits dar tot e implementat ca NUMBER) |
| Coloana `XRP_LINIE_IS_WITH_VAT` are valori string lungi ("LINE_INCLUDE_VAT") | `VARCHAR2(40)` — suficient |
| Memory CDB cu 3 PDB-uri pe 4 GB Docker | Acceptabil pentru volumul nostru; dacă apar erori SGA, bump Docker la 6 GB |

---

## 11. Decizii respinse (cu motiv)

| Alternativă | Motiv respingere |
|---|---|
| Oracle 19c EE per curs | Setup ~30 min; pentru 21c XE rulează imediat; diferențe tehnice marginale |
| Native PARTITION BY LIST | "Optimizare intra-nod", nu fragmentare; risc de pierdere puncte pe transparență |
| Triggere cu DB links pentru FK cross-PDB (fără MV) | Performanță slabă la insert; nu acoperă cerința "sincronizare replicate" |
| Fragmentare orizontală pe YEAR | 6 fragmente (2021–2026), prea multe pentru clarity; FN3 normale, dar argumentare slabă |
| Fragmentare orizontală pe TipDoc | F vs I sunt natural co-localizate; justificare distribuție vagă |
| Vertical fragmentation pe PUBLIC/PRIVATE | Split 13/3 inegal; argumentare de securitate slabă pentru context academic |

---

## 12. Referințe

- `MODBD_HANDOFF.md` (rădăcina proiectului) — contextul complet, infrastructura, deciziile de subset
- Curs PDF `ilovepdf_merged.pdf` — capitole 1–5 (introducere, modelare, control semantic, procesare cereri, optimizare) + Anexa de instalare ARM
- Cerințe oficiale: `Cerinte si barem proiect MODBD IF 2025-2026 (1).pdf`
- CSV-uri sursă: `/Users/octav/MODBD/modbd/*.csv` (15 fișiere, headere cu BOM UTF-8)
- Scripturi DDL deja rulate: `/Users/octav/MODBD/modbd/oracle/01_create_pdbs.sql`, `02_create_users.sql`
