# Handoff Proiect MODBD — Context pentru Claude (PC nou)

> **Pentru Claude:** Citește integral acest document înainte să răspunzi utilizatorului. Conține tot contextul deciziilor luate până acum pe alt PC, ca să continuăm fără să refacem analiza. Utilizatorul vorbește română — răspunde în română.

---

## 1. Despre ce e vorba

**Proiect universitar**: *Metode de Optimizare și Distribuire în Baze de Date* (MODBD), Universitatea București, FMI, an universitar 2025-2026.

**Obiectiv proiect**: Construirea unei **baze de date distribuite în Oracle** plecând de la o BD OLTP existentă. Trei module obligatorii:

| Modul | Obligatoriu | Notă min |
|---|---|---|
| Analiză (raport scris) | da | 5/10 |
| Implementare BD (Oracle backend) | da | 5/10 |
| Implementare aplicație (frontend) | da | nu impus |

**Cerințe esențiale pentru BD-ul de plecare** (OLTP-ul "sursă"):
- Minim **10 entități independente** (obligatoriu)
- Minim **1 relație many-to-many** (obligatoriu)
- Normalizare **FN3** (obligatoriu)
- Volum de date suficient pentru fragmentare

**Cerințe esențiale pentru BD distribuită**:
- Multiple BD-uri locale + 1 BD globală
- Transparență pentru fragmente verticale/orizontale/replicate
- Sincronizare relații replicate
- Toate constrângerile de integritate
- O cerere SQL complexă optimizată (cost-based + rule-based)

**PDF-ul cu cerințele oficiale** (dacă utilizatorul mai are nevoie): `Cerinte si barem proiect MODBD IF 2025-2026.pdf` (în Downloads de pe celălalt PC).

---

## 2. Status actual

✅ **TERMINAT** pe celălalt PC:
1. Analiză exhaustivă a bazei de date sursă (SQL Server, ~280 tabele, ~52M rânduri)
2. Decizie subset: **15 tabele** (12 entități + 3 M:N)
3. Selecție subset de date: **10 clienți** anonimizați
4. Generare query-uri SQL Server de extragere
5. Anonimizare date sensibile (cod client, denumire client, agent)
6. Curățare coloane: **95 col din 202 (-53%)**
7. **Export CSV-uri** (utilizatorul are fișierele pe noul PC)

⏳ **DE FĂCUT** pe noul PC:
1. Generare DDL Oracle pentru cele 15 tabele (refactorizate la FN3)
2. Import CSV-uri în Oracle
3. Decidere arhitectură distribuție (3 schemas vs 3 PDBs vs 3 instances)
4. Implementare fragmentări (orizontală primară/derivată + verticală)
5. Database links + transparență
6. Sincronizare replicate
7. Optimizare cerere SQL complexă (RBO + CBO)
8. Aplicație front-end (decizie tehnologie încă deschisă)

---

## 3. Sursa originală a datelor (context)

Datele provin dintr-o BD SQL Server numită `Integration`, sub-domeniu **distribuție B2B fashion** (încălțăminte/articole vestimentare, cu zone comerciale în România + Cehia + Slovacia + alte țări). 

**Prefixe relevante în SQL Server**:
- `DISTR_*` = tabele OLTP curate cu FK explicite (distribuție comercială)
- `IMPORT_ORS_MS_ITEMS*` = catalog produse (denormalizat, refactorizat la export)

**NU se folosesc** tabelele cu prefix: TEMP_, ZZZ_DE_STERS_, DEV_, _OLD, _copy, monthly snapshots.

---

## 4. Subset-ul de 15 tabele

### Schema relațională (vedere de ansamblu)

```
                    ┌──────────┐
                    │  ZONE    │◄──────┐
                    └──────────┘       │
                         ▲             │ M:N
                         │             │
                ┌────────┴────┐    ┌───┴──────────┐
                │  CLIENTI    │    │  AGENTI      │
                └─────────────┘    └──────────────┘
                         ▲             ▲
                         │             │
                         │       ┌─────┴──────────────────┐
                         │       │  ZONE_AGENTI (M:N)     │
                         │       └────────────────────────┘
                         │
                         │       ┌────────────────────────┐
                         │       │  INTERVALE_PLATA       │
                         │       └────────────────────────┘
                         │                ▲
                         │                │
                         │       ┌────────┴───────────────┐
                         │       │  ZONE_INTERVALE_PLATA  │ M:N
                         │       │  (intre ZONE si        │
                         │       │   INTERVALE_PLATA)     │
                         │       └────────────────────────┘
                         │                ▲
                         │                │
                         │       ┌────────┴───────────────┐
                         │       │  INTERVALE_PLATA_ZILE  │
                         │       └────────────────────────┘
                         │
                         │       ┌────────────────────────┐
                         └───────┤  CLIENTI_CONTACTE      │
                                 └────────────────────────┘
                                 
                  ┌──────────────────────┐
                  │  FISE_CLIENTI        │ (header documente)
                  │  (linkat la CLIENTI  │
                  │   prin COD_CLIENT)   │
                  └──────────────────────┘
                          ▲
                          │
                          │ M:N (linie document)
                  ┌───────┴──────────────┐
                  │  LINII_DOC           │
                  └──────────────────────┘
                          │
                          │ via ITEM_CODE
                          ▼
                  ┌──────────────────────┐         ┌──────────┐
                  │  MS_ITEMS (produse)  │────────►│ BRANDS   │
                  └──────────────────────┘         └──────────┘
                          │                        ┌──────────┐
                          ├──────────────────────►│ CATEGORY │
                          │                        └──────────┘
                          │                        ┌──────────┐
                          ├──────────────────────►│ TYPE     │
                          │                        └──────────┘
                          │                        ┌──────────┐
                          └──────────────────────►│ SEASONS  │
                                                   └──────────┘
```

### Cele 3 relații M:N

1. **`DISTR_ZONE_AGENTI`** — zone ↔ agenți
2. **`DISTR_ZONE_INTERVALE_PLATA`** — zone ↔ termene plată
3. **`DISTR_ALLDOCS_FISE_CLIENTI_LINII_DOC`** — facturi ↔ produse (cheia compusă `NrDocument` + `DocTypeXRP`)

### Inventar tabele (cu mapare CSV)

| # | Nume tabel (SQL Server) | Rol | Cols păstrate | CSV |
|---|---|---|---|---|
| 1 | `DISTR_CLIENTI` | Clienți distribuție | 7 | `01_DISTR_CLIENTI.csv` |
| 2 | `DISTR_ZONE` | Zone comerciale | 5 | `02_DISTR_ZONE.csv` |
| 3 | `DISTR_CLIENTI_CONTACTE` | Email-uri clienți/agenți | 3 | `03_DISTR_CLIENTI_CONTACTE.csv` |
| 4 | `DISTR_ZONE_AGENTI` | M:N zone↔agenți | 5 | `04_DISTR_ZONE_AGENTI.csv` |
| 5 | `DISTR_AGENTI` | Agenți vânzări | 4 | `05_DISTR_AGENTI.csv` |
| 6 | `DISTR_ZONE_INTERVALE_PLATA` | M:N zone↔termene | 5 | `06_DISTR_ZONE_INTERVALE_PLATA.csv` |
| 7 | `DISTR_INTERVALE_PLATA` | Termene plată | 2 | `07_DISTR_INTERVALE_PLATA.csv` |
| 8 | `DISTR_INTERVALE_PLATA_ZILE` | Detaliu termene (zile) | 4 | `08_DISTR_INTERVALE_PLATA_ZILE.csv` |
| 9 | `DISTR_ALLDOCS_FISE_CLIENTI` | Header documente | 15 | `09_DISTR_ALLDOCS_FISE_CLIENTI.csv` |
| 10 | `DISTR_ALLDOCS_FISE_CLIENTI_LINII_DOC` | M:N linii doc | 13 | `10_DISTR_ALLDOCS_FISE_CLIENTI_LINII_DOC.csv` |
| 11 | `IMPORT_ORS_MS_ITEMS` | Produse | 15 | `11_IMPORT_ORS_MS_ITEMS.csv` |
| 12 | `IMPORT_ORS_MS_ITEMS_BRANDS` | Branduri | 4 | `12_IMPORT_ORS_MS_ITEMS_BRANDS.csv` |
| 13 | `IMPORT_ORS_MS_ITEMS_SEASONS` | Sezoane | 5 | `13_IMPORT_ORS_MS_ITEMS_SEASONS.csv` |
| 14 | `IMPORT_ORS_MS_ITEMS_TYPE` | Tipuri produse | 4 | `14_IMPORT_ORS_MS_ITEMS_TYPE.csv` |
| 15 | `IMPORT_ORS_MS_ITEMS_CATEGORY` | Categorii produse | 4 | `15_IMPORT_ORS_MS_ITEMS_CATEGORY.csv` |
| | | | **95 col total** | |

> **NOTĂ**: Numele fișierelor CSV sunt **sugerate** — utilizatorul poate să le aibă altfel salvate. Întreabă-l să-ți spună numele exact înainte să generezi scripturi de import.

---

## 5. Schema detaliată pe fiecare tabel (pentru DDL Oracle)

### 1. `DISTR_CLIENTI` (7 col)
- `ID` (bigint, PK)
- `COD_CLIENT` (nvarchar 60) — *anonimizat: `CLI000001`..`CLI000010`*
- `DENUMIRE_CLIENT` (nvarchar 200) — *adăugată, anonimizat*
- `TIP_CLIENT` (nvarchar 12) — toți sunt `CLIENT`
- `ID_ZONA` (bigint, FK → DISTR_ZONE.ID)
- `START_DATE` (date)
- `END_DATE` (date, nullable)

### 2. `DISTR_ZONE` (5 col)
- `ID` (bigint, PK)
- `COD_ZONA` (nvarchar 40)
- `DEN_ZONA` (nvarchar 80)
- `TIP_ZONA` (nvarchar 10)
- `PARENT_ZONA_ID` (bigint, nullable, self-FK)

### 3. `DISTR_CLIENTI_CONTACTE` (3 col)
- `COD_CLIENT` (nvarchar 60, FK → DISTR_CLIENTI.COD_CLIENT)
- `EMAIL_CLIENT` (nvarchar 1000) — *fictiv: `contact-CLI00000X@example.com`*
- `EMAIL_AGENT` (nvarchar 1000) — *fictiv: `agent-CLI00000X@example.com`*

### 4. `DISTR_ZONE_AGENTI` — M:N (5 col)
- `ID` (bigint, PK)
- `ID_ZONA` (bigint, FK → DISTR_ZONE.ID)
- `ID_AGENT` (bigint, FK → DISTR_AGENTI.ID)
- `START_DATE` (date)
- `END_DATE` (date, nullable)

### 5. `DISTR_AGENTI` (4 col)
- `ID` (bigint, PK)
- `COD_AGENT` (nvarchar 20) — *anonimizat: `AG001`, `AG002`, ...*
- `NUME_AGENT` (nvarchar 100) — *fictiv: `Agent Fictiv 1`, ...*
- `EMAIL` (nvarchar 200) — *fictiv: `agent1@example.com`, ...*

### 6. `DISTR_ZONE_INTERVALE_PLATA` — M:N (5 col)
- `ID` (bigint, PK)
- `ID_ZONA` (bigint, FK → DISTR_ZONE.ID)
- `ID_INTERVAL` (bigint, FK → DISTR_INTERVALE_PLATA.ID)
- `START_DATE` (date)
- `END_DATE` (date, nullable)

### 7. `DISTR_INTERVALE_PLATA` (2 col)
- `ID` (bigint, PK)
- `DEN_INTERVAL` (nvarchar 60)

### 8. `DISTR_INTERVALE_PLATA_ZILE` (4 col)
- `ID_INTERVAL` (bigint, FK → DISTR_INTERVALE_PLATA.ID)
- `PER_ZILE` (nvarchar 40)
- `ZILE_START` (int)
- `ZILE_END` (int, nullable)

### 9. `DISTR_ALLDOCS_FISE_CLIENTI` (15 col) — header documente
- `ID` (bigint, PK)
- `NrDocument` (nvarchar 30)
- `NrDocInitial` (nvarchar 30, nullable)
- `TipDoc` (char 1) — `F` (factură) / `I` (încasare)
- `DocTypeXRP` (char 3) — `INV`, `PMT`, `CRM`, `PPM`, `REF`, `RPM`, `DRM`, `VRF`
- `DataDocEfectiva` (date) — **data reală a documentului** (NU folosi `DataDoc` care e altceva)
- `DataScad` (date, nullable)
- `Semn` (int) — +1 sau -1 (direcția contabilă)
- `Moneda` (nvarchar 10) — `RON`, `EUR`, `CZK`, rar `USD`
- `AmountDoc` (decimal 17, 2)
- `AmountDoc_RON` (decimal 17, 2)
- `PlataPrin` (nvarchar 20, nullable)
- `CodClient` (nvarchar 60) — *anonimizat, leagă cu CLIENTI.COD_CLIENT*
- `DenumireClient` (nvarchar 200) — *anonimizat*
- `ClasaClient` (nvarchar 20) — toate sunt `DISTR`

**Cheia compusă logică**: `(NrDocument, DocTypeXRP)` — folosită pentru LINII_DOC

### 10. `DISTR_ALLDOCS_FISE_CLIENTI_LINII_DOC` — M:N (13 col)
- `ID` (bigint, PK)
- `DocTypeXRP` (char 3) — parte din FK către FISE_CLIENTI
- `NrDocument` (nvarchar 30) — parte din FK către FISE_CLIENTI
- `ITEM_CODE` (nvarchar 50) — FK către MS_ITEMS.ITEM_CODE
- `ITEM_QTY` (decimal 13, 2)
- `XRP_DOC_VALOARE_fara_TVA` (decimal 9, 2) — **totaluri document**
- `XRP_DOC_TVA` (decimal 9, 2)
- `XRP_DOC_PROCENT_TVA` (decimal 9, 2)
- `XRP_DOC_VALOARE_TOTALA` (decimal 9, 2)
- `XRP_LINIE_IS_WITH_VAT` (nvarchar 40) — **valori pe linie (per produs)**
- `XRP_LINIE_VALOARE_fara_TVA` (decimal 9, 2)
- `XRP_LINIE_TVA` (decimal 9, 2)
- `XRP_LINIE_PROC_TVA` (decimal 9, 2)

> **Important**: `XRP_DOC_*` = totaluri pe documentul întreg; `XRP_LINIE_*` = valori pentru linia/produsul respectiv. **Ambele sunt utile** (confirmat de user).

### 11. `IMPORT_ORS_MS_ITEMS` (15 col)
- `ID` (bigint, PK)
- `ITEM_CODE` (varchar 50)
- `ITEM_NAME` (varchar 350)
- `ITEM_DESCRIPTION` (varchar 1000, nullable)
- `BRAND_ID` (bigint, FK → BRANDS.ID, nullable)
- `SEASON_ID` (bigint, FK → SEASONS.ID, nullable)
- `ITEM_TYPE_ID` (bigint, FK → TYPE.ID, nullable)
- `CATEGORY_ID` (bigint, FK → CATEGORY.ID, nullable) — *în SQL Server este `CLS_CLASS`, aliasat la export*
- `VAT` (float, nullable)
- `LAST_COST_PRICE` (numeric 9, 2, nullable)
- `MAIN_BARCODE` (varchar 20, nullable)
- `SUPPLIER_CODE` (varchar 60, nullable)
- `WEIGHT` (numeric 9, 2, nullable)
- `UM` (varchar 10, nullable)
- `ACTIVE` (numeric, nullable)

### 12. `IMPORT_ORS_MS_ITEMS_BRANDS` (4 col)
- `ID` (bigint, PK)
- `CODE` (varchar 3)
- `BRAND` (varchar 50, nullable)
- `DESCRIPTION` (varchar 300, nullable)

### 13. `IMPORT_ORS_MS_ITEMS_SEASONS` (5 col)
- `ID` (bigint, PK)
- `CODE` (nvarchar 120, nullable)
- `DESCRIPTION` (nvarchar 40, nullable)
- `YEAR` (nvarchar 8, nullable) — *atenție: cuvânt rezervat în Oracle, redenumit `SEASON_YEAR`*
- `ACTIVE` (int, nullable)

### 14. `IMPORT_ORS_MS_ITEMS_TYPE` (4 col)
- `ID` (bigint, PK)
- `CODE` (nvarchar 4, nullable)
- `ITEM_TYPE` (nvarchar 200, nullable)
- `DESCRIPTION` (nvarchar 600, nullable)

### 15. `IMPORT_ORS_MS_ITEMS_CATEGORY` (4 col)
- `ID` (bigint, PK)
- `CODE` (varchar 2, nullable)
- `Category` (varchar 50)
- `Name` (varchar 50)

---

## 6. Cei 10 clienți selectați

Selectați după **scor de diversitate** (zone × ani × valute × tipuri doc):

| # | COD orig | COD fake | Zonă | Docs | Ani | Valute | Tip doc |
|---|---|---|---|---|---|---|---|
| 1 | 41100456 | CLI000001 | SLOVACIA | 139 | 2021-2026 (6) | EUR | 7 |
| 2 | 411000547 | CLI000002 | ARDEAL | 456 | 2022-2026 (5) | RON | 7 |
| 3 | 411002917 | CLI000003 | MOLDOVA | 290 | 2022-2026 (5) | RON | 7 |
| 4 | 411000640 | CLI000004 | SUD | 272 | 2022-2026 (5) | RON | 7 |
| 5 | 41100408 | CLI000005 | SLOVACIA | 89 | 2021-2026 (6) | RON+EUR | 5 |
| 6 | CZ5853061753 | CLI000006 | CEHIA | 67 | 2023-2026 (4) | EUR+CZK | 6 |
| 7 | CZ6151300958 | CLI000007 | CEHIA | 56 | 2023-2026 (4) | RON+EUR+CZK | 4 |
| 8 | 41100470 | CLI000008 | SLOVACIA | 144 | 2021-2026 (6) | RON+EUR | 5 |
| 9 | 411000077 | CLI000009 | ARDEAL | 236 | 2021-2026 (6) | RON | 6 |
| 10 | 41100238 | CLI000010 | MOLDOVA | 297 | 2021-2026 (6) | RON | 6 |

**Acoperire pentru argumentări fragmentare**:
- 5 zone distincte (ARDEAL, SUD, MOLDOVA, SLOVACIA, CEHIA)
- 6 ani (2021-2026)
- 3 valute (RON, EUR, CZK)
- 7 tipuri de documente (INV, PMT, CRM, PPM, REF, RPM, DRM)
- Domestic (RO) vs extern (SK/CZ) — argumente pentru replicare

**Cantități CSV așteptate** (de validat când se face import):
- DISTR_CLIENTI: 10
- DISTR_ZONE: 5
- DISTR_AGENTI: 3-5
- FISE_CLIENTI: ~2.000 documente
- LINII_DOC: ~6.000-8.000 linii
- MS_ITEMS: ~300-600 produse distincte

---

## 7. Decizii deja luate

| Decizie | Detaliu | De ce |
|---|---|---|
| Domeniu BD | Distribuție B2B fashion | Coerență de domeniu, joncțiuni curate prin `CodClient` text |
| Eliminat `FISE_TRANZACTII` | Tabel analitic opțional, scos | Avem deja 15 tabele, simplifică modelul |
| Eliminat `CodLocatieClient`/`DenumireLocatieClient` | Coloane scoase din FISE_CLIENTI | Anonimizarea cauza bug (cartesian product), nu sunt esențiale |
| `DataDocEfectiva` în loc de `DataDoc` | În FISE_CLIENTI | `DataDoc` nu e data reală, `DataDocEfectiva` da |
| `XRP_DOC_*` ȘI `XRP_LINIE_*` păstrate | În LINII_DOC | Sunt complementare (doc total vs linie individuală) |
| `CLS_CLASS` → `CATEGORY_ID` | Aliasat la export | Mai clar (e FK către CATEGORY) |
| Anonimizare denumire client | Adăugată ca coloană nouă în CLIENTI | User a vrut explicit |

---

## 8. Decizii deschise (de luat cu utilizatorul)

### A. Instalare Oracle
- Oracle XE 21c (free, recomandat pentru proiect)?
- Docker?
- Oracle Cloud Free Tier?
- Alt setup?

### B. Arhitectura distribuției
**Trei opțiuni pentru cele "3 baze de date locale"**:

1. **3 schemas într-o singură instanță** (cel mai simplu pe Windows)
   - Folosesc synonyms + db links între schemas
   - Acoperă 100% cerințele
2. **3 PDB-uri într-un CDB** (compromis, arată "enterprise")
3. **3 instanțe Oracle separate** (cel mai realist, consumă resurse)

### C. Distribuirea propusă (independent de A și B)
**Nod 1 — `BD_DISTRIBUTIE`** (CRM/Comercial):
ZONE, AGENTI, CLIENTI, CLIENTI_CONTACTE, INTERVALE_PLATA, INTERVALE_PLATA_ZILE, ZONE_AGENTI, ZONE_INTERVALE_PLATA

**Nod 2 — `BD_CATALOG`** (Produse):
BRANDS, CATEGORY, TYPE, SEASONS, MS_ITEMS
→ **Fragmentare verticală** pe MS_ITEMS: split în PRODUS_CORE (cod, nume, FK-uri) + PRODUS_EXTRA (preț, greutate, barcode etc.)

**Nod 3 — `BD_VANZARI`** (Tranzacții):
FISE_CLIENTI, LINII_DOC
→ **Fragmentare orizontală primară** pe FISE_CLIENTI: pe `YEAR(DataDocEfectiva)` SAU pe `Moneda` SAU pe `TipDoc`
→ **Fragmentare orizontală derivată** pe LINII_DOC (urmează fragmentarea FISE_CLIENTI prin `NrDocument`+`DocTypeXRP`)

**Replicate pe toate nodurile**: BRANDS, CATEGORY, TYPE, SEASONS, INTERVALE_PLATA (lookup-uri mici)

### D. Cererea SQL complexă (cerința 9 din analiză)
Candidat: *"Top 10 agenți după valoare vândută în 2024, defalcate pe zonă și categorie de produs"* — folosește date din toate 3 nodurile (agent → zonă → client → fise → linii → produs → categorie).

### E. Tehnologia front-end (cerința modulul 3)
Încă nedecis (Java? .NET? Python? Vorbește cu utilizatorul).

---

## 9. Pași concreți recomandați (în ordine)

1. **Confirmă cu utilizatorul** ce arhitectură Oracle vrea (A + B mai sus)
2. **Generează DDL Oracle** pentru cele 15 tabele:
   - Mapează tipuri SQL Server → Oracle (bigint → NUMBER(19), nvarchar → NVARCHAR2 sau VARCHAR2, bit → NUMBER(1), date → DATE, datetime → TIMESTAMP)
   - Atenție la cuvinte rezervate: `YEAR` în SEASONS, `Category`/`Name` în CATEGORY (Oracle e case-insensitive cu identificatori unquoted)
   - Adaugă PK-uri și FK-uri explicite (în SQL Server multe sunt implicite)
3. **Generează scripturile de import** (SQL*Loader sau External Tables) din CSV-uri în Oracle
4. **Implementează fragmentările** conform planului din secțiunea 8.C
5. **Database links + synonyms** pentru transparență la nivel global
6. **Constrângeri de integritate globale** (între tabele din BD-uri diferite)
7. **Sincronizare relații replicate** (materialized views sau triggere)
8. **Optimizare cerere SQL complexă** — captură EXPLAIN PLAN cu RBO și CBO, propuneri de optimizare
9. **Aplicație front-end** (după ce backend-ul e gata)

---

## 10. Cerințele importante din PDF (rezumat)

### Analiză (10 puncte)
- 0.25p (obligatoriu): descriere model + obiective aplicație
- 0.5p (obligatoriu): diagrama E-R OLTP inițial (min 10 entități, min 1 M:N, FN3)
- 0.5p (obligatoriu): diagrama conceptuală OLTP
- 0.25p (obligatoriu): descriere mod distribuire (nr server-e)
- 1p (obligatoriu): fragmente orizontale primare
- 0.5p (obligatoriu): fragmente orizontale derivate
- 1p: fragmente verticale (algoritm + obținere)
- 1p: verificare corectitudine fragmentări
- 0.5p: argumentare replicare
- 0.75p (obligatoriu): scheme conceptuale locale
- 2p (obligatoriu): toate constrângerile (unicitate locală/globală, PK, FK, validări)
- 0.25p: formulare cerere SQL complexă + tehnici optimizare

### Implementare BD Oracle (10 puncte)
- 0.5p (obligatoriu): creare BD-uri + utilizatori
- 1p (obligatoriu): creare relații + fragmente
- 0.5p (obligatoriu): populare cu date
- 2.5p: transparență (1p vertical + 1p orizontal + 0.5p tabele în alte BD-uri)
- 1p: sincronizare replicate
- 2p (obligatoriu): toate constrângerile (local + global)
- 1.5p: optimizare cerere SQL (RBO + CBO + sugestii)

### Aplicație Front-end (10 puncte, fără minim)
- 3p: modul CRUD pe BD locale
- 1p: modul vizualizare BD globală
- 2p: vizualizare la nivel global a operațiilor LMD locale
- 3p: propagare operații LMD globale la nivele locale

---

## 11. Cum să continui în noua sesiune

**Primul lucru** când utilizatorul deschide o nouă sesiune cu Claude:
1. Citește integral acest document
2. Întreabă utilizatorul:
   - Unde sunt CSV-urile (calea pe noul PC)
   - Ce variantă de Oracle a instalat / preferă
   - Ce arhitectură de distribuție vrea (secțiunea 8.B)
3. Doar după ce ai răspunsurile, începe să generezi DDL-ul Oracle

**Nu reface** analiza — datele și deciziile sunt stabile. Continuă de la pasul "Generare DDL Oracle".

---

## 12. Fișiere generate până acum (pe celălalt PC)

- `Cerinte si barem proiect MODBD IF 2025-2026.pdf` — cerințele oficiale (utilizatorul trebuie să-l aibă și pe noul PC)
- `extragere_date_proiect_MODBD.sql` — script SQL Server de extragere (nu mai e nevoie pe noul PC; CSV-urile sunt deja exportate)
- `analiza_null_proiect_MODBD.sql` — script auxiliar (nu mai e nevoie)
- CSV-urile (15 fișiere, conform tabelului din secțiunea 4)

---

**End of handoff.**

---

## 13. Sesiune 2026-05-14 — progres + decizii noi

### Infrastructură (gata)
- Docker Desktop pe Mac M4 (macOS 26.4.1), Rosetta disponibil
- Imagine `gvenzl/oracle-xe:21-slim-faststart` (linux/amd64) pulled
- Container `oracle-modbd` rulând, port 1521 expus, CSV-uri montate la `/csv`
- Parolă SYS/SYSTEM: `ModbdSecret123`
- Volume persistent: `oracle-modbd-data` (`/opt/oracle/oradata`)

### Structură PDB-uri (creată)
- XEPDB1 șters
- 3 PDB-uri create + auto-open la restart: `DISTRIBUTIE`, `CATALOG`, `VANZARI`
- Tablespace `USERS` în fiecare (datafile `/opt/oracle/oradata/XE/<pdb>/users01.dbf`)
- Utilizatori (convenția cursului — role `sgbd_role` + user `sgbd_<pdbname>` parolă `oracle`):
  - DISTRIBUTIE → `SGBD_DISTRIBUTIE` / `oracle`
  - CATALOG → `SGBD_CATALOG` / `oracle`
  - VANZARI → `SGBD_VANZARI` / `oracle`
- Role `sgbd_role` în fiecare PDB cu grant-urile complete din curs (CONNECT, RESOURCE, CREATE TABLE/VIEW/MV/SYNONYM/PROCEDURE/SEQUENCE/TRIGGER/TYPE, QUERY REWRITE, SELECT_CATALOG_ROLE, ALTER SESSION, SELECT ANY DICTIONARY, CREATE [PUBLIC] DATABASE LINK, CREATE [PUBLIC] SYNONYM)
- SYS parolă rămâne `ModbdSecret123` (cursul folosește `Admin#DB1` ca exemplu, nu impune)

### CSV-uri (verificate)
- Toate 15 au header acum (DOCS_LINES.csv s-a corectat în această sesiune)
- BOM UTF-8 la început (de manevrat în SQL*Loader cu `CHARACTERSET UTF8`)
- `NULL` apare ca string în CSV — necesită `NULLIF col='NULL'` în control files
- Volume reale: CLIENTI 10, ZONE 5, AGENTI 6, CONTACTE 5, INTERVALE_PLATA 2, ZONE_AGENTI 11, ZONE_INTERVALE_PLATA 5, INTERVALE_PLATA_ZILE 8, ITEMS_CATEGORY 15, ITEMS_TYPE 3, ITEMS_SEASONS 17, BRANDS 131, **ITEMS 3192**, DOCS_HEADERS 2048, DOCS_LINES 5598

### Fișiere SQL generate (în `/Users/octav/MODBD/modbd/oracle/`)
- `01_create_pdbs.sql` — creează cele 3 PDB-uri (rulat ✓)
- `02_create_users.sql` — creează USERS tablespace + utilizatori app (rulat ✓)
- `ddl/`, `sqlldr/` — directoare goale, pregătite pentru pasul următor

### Decizii arhitecturale luate (brainstorming session)
| Decizie | Alegere | Notă |
|---|---|---|
| Oracle install | XE 21c în Docker (Apple Silicon + Rosetta) | DONE |
| Arhitectură 3 BD-uri | 3 PDB-uri în CDB | DONE |
| Frag. orizontală FISE_CLIENTI | **Moneda** (RON vs EUR/CZK) | Aliniere cu argument geografic RO/extern |
| Frag. orizontală derivată LINII_DOC | Urmează FISE_CLIENTI prin `NrDocument`+`DocTypeXRP` | Implicit din decizia de mai sus |
| Frag. verticală MS_ITEMS | **CORE** (id, cod, nume, FK-uri, activ) + **EXTRA** (descriere, TVA, cost, barcode, furnizor, greutate, UM) | Split 8/8 |
| Strategie cross-PDB FK | **Replicare agresivă via Materialized Views** | Acoperă 2 cerințe (constrângeri + sync replicate) |
| Implementare fragmente | **Tabele fizice separate + VIEW transparent** | View = transparența cerută la 1p+1p+0.5p |
| Cererea SQL complexă | **Top 10 agenți după valoare vândută pe zonă și categorie** (2024) | Touchează toate 3 PDB-uri, 7+ joins, agregare+sort+limit |

### De continuat (când se reia)
**Pasul curent**: brainstorming în skill `superpowers:brainstorming`, am ajuns la finalul fazei de întrebări clarificatoare. Următorul pas e prezentarea designului pe secțiuni (arhitectură, componente, data flow, transparență, sync, constraints, optimizare), apoi spec doc în `docs/superpowers/specs/2026-05-14-modbd-bd-oracle-design.md`, apoi `superpowers:writing-plans`.

**Comenzi utile la repornire**:
```bash
# Pornește containerul (dacă e oprit)
docker start oracle-modbd
# Așteaptă să fie ready
until docker logs oracle-modbd 2>&1 | grep -q "DATABASE IS READY TO USE"; do sleep 3; done
# Verificare PDB-uri active
docker exec -i oracle-modbd sqlplus -s sys/ModbdSecret123@localhost:1521/XE as sysdba <<< $'select con_id,name,open_mode from v$pdbs;\nexit'
# Conectare ca app user
docker exec -it oracle-modbd sqlplus app_dist/ModbdSecret123@localhost:1521/DISTRIBUTIE
```

---

## 14. Sesiunea 2 (2026-05-14, continuare) — execuție subagent-driven

### Documente generate
- `docs/superpowers/specs/2026-05-14-modbd-bd-oracle-design.md` (888 linii) — design complet aprobat
- `docs/superpowers/plans/2026-05-14-modbd-implementation.md` (~2400 linii) — 17 task-uri TDD-style

### Convenții aliniate la curs
- Utilizatori redenumiți: `SGBD_DISTRIBUTIE`/`SGBD_CATALOG`/`SGBD_VANZARI` parolă `oracle`
- Role `sgbd_role` cu grant-urile complete din curs
- SYS parolă rămâne `ModbdSecret123`

### Git tracking
- Repo init local în `/Users/octav/MODBD/.git`
- Identitate LOCAL only (NU global): `octavoprinoiu17@gmail.com` / `Octavian Oprinoiu`
- Global config rămâne neschimbat (`octavian.oprinoiu@otter.ro`)
- Commit-uri single-line, FĂRĂ `Co-Authored-By:` tags

### Task-uri executate (17/17 — TOATE COMPLETATE) ✅
| # | SHA | Descriere |
|---|---|---|
| 1 | `67a4cab` | git init + initial commit (22 files) |
| 2 | `e59230c` | CSV_DIR directory + READ+WRITE grants în toate 3 PDB-uri |
| 3 | `8b1a66d` | DDL DISTRIBUTIE (8 tabele + 8 FK) |
| 4 | `6e560c0` | Load DISTRIBUTIE (5+6+10+5+2+8+11+5 rânduri) |
| 5 | `860a9a4` | DDL CATALOG (6 tabele + V_ITEMS + 3 triggere INSTEAD OF) |
| 6 | `365c2a4` | Load CATALOG (131+15+3+17+3192+3192 rânduri) |
| 7 | `8c0666c` | DDL VANZARI fragments (FISE RO/EXT + LINII RO/EXT) |
| 8 | `d483f08` | Load VANZARI (1555+493 fise, 3831+1767 linii — split per Moneda) |
| 9 | `fcc6f58` | View-uri UNION ALL + 5 triggere INSTEAD OF |
| 10 | `c5e6faf` | 7 MV logs pe master (DISTRIBUTIE + CATALOG) |
| 11 | `37edf26` | DB links VANZARI → DISTRIBUTIE + CATALOG |
| 12 | `2288a33` | 7 MV-uri replicate + 4 FK cross-PDB *(80 orphans LINII șterse: item_codes orfane în datele sursă)* |
| 13 | `712aea4` | DBMS_SCHEDULER job FAST refresh @ 60s (testat end-to-end) |
| 14 | `d7b918f` | Trigger agregat coerență sum_doc ↔ sum_linii |
| 15 | `b381704` | 8 indecși + DBMS_STATS gathered |
| 16 | `04de288` | Cererea complexă top 10 agenți 2024 + 3 EXPLAIN PLAN (RBO=hash 2771358336 / CBO=cost 70 / DRIVING_SITE=cost 46 = 40% îmbunătățire) |
| 17 | `e7181ab` | End-to-end validation — toate 5 testele PASS |

### Volume finale
- DISTRIBUTIE: 5+6+10+5+2+8+11+5 = 52 rânduri
- CATALOG: 131+15+3+17+3192+3192 = 6.550 rânduri
- VANZARI: 1555+493=2.048 documente, 3806+1712=5.518 linii (80 orfane eliminate la enforcement FK)
- MV-uri replicate în VANZARI: 10+5+3192+131+15+3+17 = 3.373 rânduri

### Cerințe baremul oficial — acoperite
| Punctaj | Cerință | Status |
|---|---|---|
| 0.5p obligatoriu | Creare BD-uri + utilizatori | ✓ Tasks 1-2 |
| 1p obligatoriu | Creare relații + fragmente | ✓ Tasks 3, 5, 7 |
| 0.5p obligatoriu | Populare cu date | ✓ Tasks 4, 6, 8 |
| 2.5p | Transparență (vertical + orizontal + cross-BD) | ✓ Tasks 5 (V_ITEMS), 9 (V_FISE/V_LINII), 11 (DB links) |
| 1p | Sincronizare replicate | ✓ Tasks 10, 12, 13 (MV logs + 7 MV-uri + job 60s, sync verificat E2E) |
| 2p obligatoriu | Toate constrângerile | ✓ DDL local (Tasks 3, 5, 7) + cross-PDB FK (Task 12) + agregat (Task 14) |
| 1.5p | Optimizare cerere SQL (RBO + CBO + sugestii) | ✓ Tasks 15-16 (indexes + stats + 3 EXPLAIN PLAN comparate) |

### Lecții învățate (de aplicat la task-urile 8, 15 care încarcă CSV-uri rămase)

**CRITICAL pentru toate external tables**:
1. **CSV-urile au CRLF** — adaugă **`LRTRIM`** după `OPTIONALLY ENCLOSED BY '"'`. Fără asta, ultima coloană pe fiecare rând are `\r` trailing care strică `CASE WHEN col='NULL'` și `TO_DATE`/`TO_NUMBER`.
2. **Mount `/csv` e read-only** (`:ro` în `docker run`) — adaugă **`NOLOGFILE NOBADFILE NODISCARDFILE`** în ACCESS PARAMETERS. Altfel ORACLE_LOADER eșuează încercând să scrie loguri.
3. **Coloana `YEAR` din ITEMS_SEASONS.csv** se mapează la `season_year` în tabel — Oracle citește pozițional, nu după nume header, deci numirea coloanelor în external table e arbitrară.
4. **`'NULL'` în CSV** — wrap fiecare coloană nullable cu `NULLIF(col, 'NULL')` sau `CASE WHEN col='NULL' THEN NULL ELSE ... END`.
5. **Format dat**: `TO_DATE(col, 'YYYY-MM-DD')` pentru DATE; `BINARY_DOUBLE` pentru float.

**CRITICAL pentru subagent dispatch**:
- Sub-agent-ul Task 4 a **fabricat date fake** când a întâlnit eroare KUP-04074 (permission). Trebuie ZIS EXPLICIT: "dacă external tables eșuează, STOP și raportează BLOCKED, NU improviza cu INSERT VALUES".

### Task-uri rămase (7-17)

**Task 7**: DDL VANZARI fragmente (FISE_CLIENTI_RO/EXT + LINII_DOC_RO/EXT) — doar DDL, fără date.
**Task 8**: Load VANZARI cu split orizontal pe Moneda (RON vs ≠RON). Folosește external table peste DOCS_HEADERS.csv și DOCS_LINES.csv, apoi 2 INSERT-uri per CSV cu filter. **Atenție LRTRIM + NOLOGFILE** + ordinea coloanelor DOCS_HEADERS.csv (cu header `ID,NrDocument,NrDocInitial,TipDoc,DocTypeXRP,DataDocEfectiva,DataScad,Semn,Moneda,AmountDoc,AmountDoc_RON,PlataPrin,CodClient,DenumireClient,ClasaClient`).
**Task 9**: View-uri UNION ALL pe VANZARI + INSTEAD OF triggers.
**Task 10**: MV logs pe DISTRIBUTIE + CATALOG (7 tabele master).
**Task 11**: DB links VANZARI→DISTRIBUTIE și →CATALOG + smoke test.
**Task 12**: 7 MV-uri replicate în VANZARI + 4 FK cross-PDB locale.
**Task 13**: DBMS_SCHEDULER job 60s refresh FAST.
**Task 14**: Trigger agregat pentru coerență `amount_doc` vs sum linii.
**Task 15**: 8 indecși pe fact tables + DBMS_STATS.
**Task 16**: Query complex (top 10 agenți 2024) + 3 EXPLAIN PLAN (RBO/CBO/DRIVING_SITE).
**Task 17**: End-to-end validation script (counts + transparency + FK + sync).

### Status final: IMPLEMENTARE COMPLETĂ ✅

Modulul 2 al proiectului (Implementare BD Oracle) este complet. Toate 17 task-uri rulate, 18 commit-uri pe `main`, baza distribuită funcțională în Docker.

### Următorii pași în afara modulului 2

1. **Modulul 1 — Raport de Analiză** (10p): diagrama E-R, scheme conceptuale globale/locale, argumentare BEA pentru fragmentare verticală, replicare, etc. Spec-ul `2026-05-14-modbd-bd-oracle-design.md` conține toată substanța tehnică — raportul reformulează ce am implementat în formă academică.
2. **Modulul 3 — Aplicație Front-end** (10p, fără minim): CRUD pe cele 3 PDB-uri + vizualizare globală + propagare LMD. Tehnologie nedecisă încă.
