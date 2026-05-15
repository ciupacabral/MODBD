# MODBD — Bază de Date Distribuită pentru Distribuție B2B

> Proiect universitar pentru disciplina **Metode de Optimizare și Distribuire în Baze de Date** (MODBD), Facultatea de Matematică și Informatică, Universitatea București, anul universitar 2025–2026.

Acest repo conține implementarea completă a unei baze de date distribuite peste Oracle 21c Express Edition, rulând în Docker. Sistemul are 3 PDB-uri locale (DISTRIBUTIE, CATALOG, VANZARI) cu fragmentare orizontală + verticală, replicare prin materialized views și transparență totală pentru aplicația-client.

---

## Cuprins

- [Pre-cerințe](#pre-cerinte)
- [Setup rapid (one-liner)](#setup-rapid)
- [Verificare instalare](#verificare-instalare)
- [Conectare la baza de date](#conectare-la-baza-de-date)
- [Comenzi utile](#comenzi-utile)
- [Structura proiectului](#structura-proiectului)
- [Troubleshooting](#troubleshooting)

---

## Pre-cerințe

| Componenta | Versiune minimă | Notă |
|---|---|---|
| Docker Desktop | 4.30+ | Cu Rosetta activat pe Apple Silicon (Mac M1/M2/M3/M4) |
| Disc liber | ~5 GB | Imaginea Oracle XE ~2GB + datafiles ~3GB |
| RAM alocat Docker | minim 4 GB | Implicit Docker Desktop alocă 8 GB, e suficient |
| Bash | 4.0+ | Standard pe macOS și Linux |

Pentru **Apple Silicon**: imaginea Oracle XE rulează prin Rosetta (linux/amd64). Verifică în Docker Desktop → Settings → General → "Use Rosetta for x86_64/amd64 emulation" e bifat.

Pentru **Windows**: rulează `setup.sh` din WSL2 (Windows Subsystem for Linux), nu direct din PowerShell/cmd.

---

## Setup rapid

Două comenzi pentru setup complet de la zero:

```bash
git clone <URL_REPO>          # înlocuiește <URL_REPO> cu adresa GitHub
cd MODBD
./setup.sh
```

Setup-ul rulează automat 17 etape:

1. Pull imaginea Oracle XE 21c
2. Creează containerul `oracle-modbd` cu volumele necesare
3. Așteaptă inițializarea bazei (~3-5 minute la prima rulare)
4. Creează 3 PDB-uri: DISTRIBUTIE, CATALOG, VANZARI
5. Creează utilizatori app per PDB (`sgbd_distributie`, `sgbd_catalog`, `sgbd_vanzari`, parolă `oracle`)
6. Configurează directorul CSV pentru external tables
7. Rulează DDL + load pentru DISTRIBUTIE (8 tabele, 52 rânduri)
8. Rulează DDL + load pentru CATALOG (6 tabele + V_ITEMS, 6.550 rânduri)
9. Rulează DDL + load pentru VANZARI cu fragmentare orizontală (4 fragmente, 7.566 rânduri)
10. Creează view-uri UNION ALL + 5 triggere INSTEAD OF
11. Creează MV logs pe tabelele master
12. Creează database links VANZARI → DISTRIBUTIE + CATALOG
13. Creează 7 Materialized Views replicate
14. Activează 4 FK-uri cross-PDB
15. Configurează job DBMS_SCHEDULER pentru refresh @ 60s
16. Creează trigger agregat pentru coerență sume
17. Creează 8 indecși + gather statistics

La final, rulează testele end-to-end de validare (counts, transparență, FK, sincronizare MV).

**Durată totală**: 5-10 minute, în funcție de viteza conexiunii (pull imagine ~2GB).

---

## Verificare instalare

După setup, rulează:

```bash
./setup.sh --validate
```

Trebuie să vezi 5 teste cu status `PASS`:

```
Test 1: Counts globale          PASS  (52 / 6550 / 2048+5598 / 3373 MV)
Test 2: View-uri transparenta   PASS  (V_FISE = RO + EXT)
Test 3: INSTEAD OF trigger      PASS  (insert RON -> fise_clienti_ro)
Test 4: FK cross-PDB            PASS  (insert cu cod fals -> respins)
Test 5: Sincronizare MV         PASS  (refresh manual propaga delta)
```

Pentru rularea cererii SQL complexe (top 10 agenți 2024) + EXPLAIN PLAN comparativ (RBO / CBO / DRIVING_SITE):

```bash
./setup.sh --query
```

---

## Conectare la baza de date

| PDB | Connection string | Utilizator | Parolă |
|---|---|---|---|
| DISTRIBUTIE | `//localhost:1521/DISTRIBUTIE` | `sgbd_distributie` | `oracle` |
| CATALOG | `//localhost:1521/CATALOG` | `sgbd_catalog` | `oracle` |
| VANZARI | `//localhost:1521/VANZARI` | `sgbd_vanzari` | `oracle` |
| SYS (administrare) | `//localhost:1521/XE` as sysdba | `sys` | `ModbdSecret123` |

Exemple de conectare:

```bash
# Din terminal pe host (necesită sqlplus instalat local, sau folosește SQL Developer)
sqlplus sgbd_vanzari/oracle@//localhost:1521/VANZARI

# Din container (sqlplus deja prezent)
docker exec -it oracle-modbd sqlplus sgbd_vanzari/oracle@//localhost:1521/VANZARI
```

Pentru clienți grafici (SQL Developer, DBeaver, DataGrip), folosește:
- Host: `localhost`
- Port: `1521`
- Service name: `DISTRIBUTIE` / `CATALOG` / `VANZARI` / `XE`
- User/Pass: conform tabelului de mai sus

---

## Comenzi utile

```bash
./setup.sh              # setup complet (refuză dacă containerul există deja)
./setup.sh --clean      # șterge tot + setup complet de la zero
./setup.sh --validate   # rulează doar testele end-to-end
./setup.sh --query      # rulează cererea SQL complexă + EXPLAIN PLAN
./setup.sh --start      # pornește containerul oprit
./setup.sh --stop       # oprește containerul (datele persistă în volum)
./setup.sh --help       # afișează opțiunile

# Vezi log-urile Oracle live:
docker logs -f oracle-modbd

# Statusul PDB-urilor:
docker exec -it oracle-modbd sqlplus sys/ModbdSecret123@//localhost:1521/XE as sysdba <<< $'select name, open_mode from v$pdbs;\nexit'
```

---

## Structura proiectului

```
MODBD/
├── README.md                  # acest fișier
├── setup.sh                   # script master de instalare
├── MODBD_HANDOFF.md           # contextul complet al proiectului
├── docs/
│   ├── analiza/               # Raportul de Analiză (Modul 1)
│   │   ├── raport-analiza.md  # sursa markdown
│   │   ├── diagrams/          # 6 diagrame Mermaid (.mmd)
│   │   ├── reference.docx     # template Pandoc cu stiluri academice
│   │   └── output/            # .docx final (gitignored)
│   └── superpowers/
│       ├── specs/             # specificațiile de design (markdown)
│       └── plans/             # planurile de execuție
├── modbd/
│   ├── *.csv                  # 15 fișiere CSV cu datele anonimizate
│   └── oracle/
│       ├── 01_create_pdbs.sql        # creare PDB-uri (SYS)
│       ├── 02_create_users.sql       # creare utilizatori app (SYS)
│       ├── 03_csv_directory.sql      # CSV_DIR + grants (SYS)
│       └── ddl/
│           ├── 10_ddl_distributie.sql
│           ├── 11_load_distributie.sql
│           ├── 12_ddl_catalog.sql
│           ├── 13_load_catalog.sql
│           ├── 14_ddl_vanzari_fragments.sql
│           ├── 15_load_vanzari.sql
│           ├── 16_views_transparenta.sql
│           ├── 17_mv_logs.sql        # SYS, alternează PDB prin ALTER SESSION
│           ├── 18_db_links.sql
│           ├── 19_mvs_vanzari.sql
│           ├── 20_cross_pdb_fks.sql
│           ├── 21_refresh_job.sql
│           ├── 22_trigger_agregat.sql
│           ├── 23_indexes_stats.sql
│           ├── 30_query_complex.sql  # cererea complexă + EXPLAIN PLAN
│           └── 40_validare_end_to_end.sql
└── Cerinte si barem proiect MODBD IF 2025-2026 (1).pdf
```

---

## Troubleshooting

### `docker: Cannot connect to the Docker daemon`
Docker Desktop nu rulează. Pornește aplicația Docker Desktop și așteaptă să fie complet inițializată.

### `Timeout asteptand Oracle`
Imaginea s-a descărcat dar inițializarea bazei nu s-a terminat în 10 minute. Cauze frecvente:
- RAM insuficient alocat Docker (verifică ≥ 4 GB)
- Pe Apple Silicon: Rosetta nu e activat
- Disc plin

Verifică log-urile cu `docker logs oracle-modbd` și caută erori `ORA-`.

### `ORA-12541: TNS:no listener`
Containerul rulează dar listener-ul Oracle nu s-a inițializat. Așteaptă încă 30 de secunde și re-încearcă.

### `ORA-65096: invalid common user or role name`
Containerul a fost creat cu o versiune mai veche de Oracle care nu acceptă numele de utilizator fără prefix `C##`. Soluție: rulează `./setup.sh --clean` pentru un setup curat.

### Conflict de port 1521
Un alt proces folosește deja portul 1521. Verifică cu `lsof -i :1521` și oprește procesul respectiv, sau editează `setup.sh` și schimbă `-p 1521:1521` în `-p 1522:1521` (apoi conectează-te pe portul 1522).

### `MV refresh job not running`
După un restart al containerului, job-ul DBMS_SCHEDULER ar putea avea nevoie de re-activare:

```sql
-- conectat ca sgbd_vanzari pe VANZARI
EXEC DBMS_SCHEDULER.ENABLE('JOB_REFRESH_MVS');
```

### Date stale în MV-uri (în timpul testării DML cross-PDB)
Sincronizarea e cu lag de până la 60 de secunde. Pentru a forța refresh manual:

```sql
EXEC DBMS_MVIEW.REFRESH('MV_CLIENTI', 'F');
-- sau pentru toate:
EXEC DBMS_MVIEW.REFRESH('MV_CLIENTI,MV_ZONE,MV_ITEMS_CORE,MV_BRANDS,MV_ITEMS_CATEGORY,MV_ITEMS_TYPE,MV_ITEMS_SEASONS', 'FFFFFFF');
```

---

## Despre fragmentări

Sistemul implementează cele trei tipuri de fragmentări conform raportului de analiză:

- **Orizontală primară** pe `FISE_CLIENTI`, după predicatul `moneda = 'RON'` vs. `moneda <> 'RON'` → `FISE_CLIENTI_RO` (1.555 docs) și `FISE_CLIENTI_EXT` (493 docs).
- **Orizontală derivată** pe `LINII_DOC`, urmând fragmentarea owner-ului prin semijoin → `LINII_DOC_RO` (3.806 linii) și `LINII_DOC_EXT` (1.712 linii).
- **Verticală** pe `MS_ITEMS` aplicând algoritmul BEA → `ITEMS_CORE` (atribute identificare + clasificare, 7 col) și `ITEMS_EXTRA` (atribute fizice + comerciale, 7 col), unite prin view-ul `V_ITEMS`.

Detalii complete (algoritmi, calcule, verificări de corectitudine) în [docs/analiza/raport-analiza.md](docs/analiza/raport-analiza.md).

---

## Autor

Octavian Oprinoiu — Echipa `<<NUME_ECHIPA>>`

Pentru întrebări tehnice despre setup sau implementare, consultă mai întâi secțiunea Troubleshooting de mai sus.
