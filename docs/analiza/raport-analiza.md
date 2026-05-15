---
title: "Raport de Analiză — Bază de Date Distribuită pentru Distribuție B2B"
subtitle: "Modulul 1 — Metode de Optimizare și Distribuire în Baze de Date"
author: "Octavian Oprinoiu — Echipa <<NUME_ECHIPA>>"
date: "2026-05-16"
lang: ro-RO
documentclass: article
geometry: margin=2.5cm
fontsize: 12pt
mainfont: "Times New Roman"
linestretch: 1.15
---

# 1. Descrierea modelului și obiectivele aplicației

Aplicația proiectată gestionează activitatea unei rețele de distribuție business-to-business în domeniul fashion — încălțăminte și articole vestimentare — cu acoperire pe trei piețe: România (zonele ARDEAL, MOLDOVA, SUD), Slovacia și Cehia. Sursa datelor este o bază OLTP din mediul SQL Server (numită `Integration`, cu aproximativ 280 de tabele), din care am izolat un subset coerent: 12 entități independente și 3 relații many-to-many, totalizând 15 tabele cu 95 de coloane păstrate din 202 inițiale.

Selecția subsetului a urmărit două obiective. Pe de o parte, păstrarea integrității modelului relațional (toate cheile externe explicite, normalizare în Forma Normală 3). Pe de altă parte, asigurarea unui volum suficient pentru a argumenta concret deciziile de fragmentare: 10 clienți anonimizați (codurile CLI000001 până la CLI000010) acoperă cele 5 zone, 3 valute (RON, EUR, CZK), 6 ani de istoric (2021–2026) și 7 dintre cele 8 tipuri de documente — facturi, încasări, note de credit, plăți pe avans, refuzuri, retururi de plată și note de debit. În cifre brute, volumul rezultat este: 2.048 fișe de documente (header), 5.598 linii de document, 3.192 produse distincte, 131 de branduri și 17 sezoane.

Obiectivul tehnic al distribuției este descompunerea acestui model OLTP unitar într-o arhitectură cu trei noduri logice, fiecare cu o responsabilitate funcțională distinctă:

- **Nodul CRM/Comercial** — clienții, agenții, zonele și termenele de plată. Concentrează cele două dintre cele trei relații many-to-many (`ZONE_AGENTI` și `ZONE_INTERVALE_PLATA`).
- **Nodul Catalog** — produsele și clasificările lor (branduri, categorii, tipuri, sezoane). Susține fragmentare verticală pentru separarea atributelor de identificare (catalog browse) de cele administrative (cost, furnizor, dimensiuni).
- **Nodul Vânzări** — fact tables-urile de tranzacții (fișe de documente și liniile lor), fragmentate orizontal după criteriu monedă (RON vs. valute externe), aliniat cu argumentul geografic domestic/extern.

Aplicația-client va opera asupra unei vederi globale care ascunde fragmentarea: orice document poate fi consultat sau introdus prin view-uri unificate, indiferent de moneda sau locația fizică a fragmentului. La nivel fizic, fragmentele se sincronizează prin materialized views și se conectează prin database links între PDB-uri.

Pe parcursul pregătirii subsetului, am luat câteva decizii punctuale care merită menționate explicit. În primul rând, am redenumit coloana `CLS_CLASS` (denumire tehnică din sistemul ORS) ca `CATEGORY_ID` la export, pentru a evidenția faptul că este o cheie externă către tabela de categorii. În al doilea rând, am redenumit `YEAR` (sezoane) în `SEASON_YEAR`, pentru că `YEAR` este cuvânt rezervat în Oracle. În al treilea rând, am eliminat coloanele `CodLocatieClient` și `DenumireLocatieClient` din tabela de documente, deoarece anonimizarea în paralel a două coloane corelate genera produs cartezian și dubla numărul de rânduri.

Pentru protecția datelor cu caracter personal, codurile reale de client (numere cu 9 cifre) au fost înlocuite determinist cu identificatori fictivi CLI000001..CLI000010, iar numele clienților și ale agenților au fost generate ca șiruri sintetice. Operațiunea de anonimizare a fost asistată de un sistem AI pentru aplicarea consistentă a mapping-ului în toate cele 15 fișiere CSV.

# 2. Diagramele bazei de date OLTP inițiale

Modelul de pornire este OLTP-ul care servește operațiile zilnice ale rețelei de distribuție. Diagramele de mai jos surprind două nivele de detaliu: diagrama entitate–relație, care evidențiază entitățile, asocierile și cardinalitățile, și diagrama conceptuală detaliată, care adaugă atributele și cheile externe.

## 2.1. Diagrama Entitate–Relație

Modelul conține 12 entități independente și 3 relații many-to-many, depășind pragul minim de 10 entități cerut prin baremul oficial.

![Diagrama Entitate–Relație OLTP](build/01-er-oltp.png){#fig:er width=100%}

Entitățile independente sunt: `CLIENTI`, `ZONE`, `AGENTI`, `INTERVALE_PLATA`, `INTERVALE_PLATA_ZILE`, `CLIENTI_CONTACTE`, `FISE_CLIENTI`, `MS_ITEMS`, `BRANDS`, `ITEMS_CATEGORY`, `ITEMS_TYPE`, `ITEMS_SEASONS`. Relațiile many-to-many sunt:

- `ZONE_AGENTI` — un agent acoperă mai multe zone în timp, iar o zonă este acoperită succesiv de mai mulți agenți. Asocierea poartă atribute temporale (`start_date`, `end_date`) care permit reconstituirea acoperirii la o dată dată.
- `ZONE_INTERVALE_PLATA` — același pattern temporal pentru atribuirea termenelor de plată per zonă.
- `LINII_DOC` — leagă `FISE_CLIENTI` (documentele) de `MS_ITEMS` (produsele) printr-o cheie externă compusă (`nr_document`, `doc_type_xrp`) către documentul-părinte.

Tabela `ZONE` are și o auto-referință (`parent_zona_id`), care modelează ierarhia zonelor (de exemplu, o zonă-părinte „RO" cu subzonele ARDEAL, MOLDOVA, SUD).

## 2.2. Diagrama conceptuală

Diagrama conceptuală include atributele fiecărei entități, identificarea cheilor primare și externe și cardinalitățile precise (notație Crow's foot). Tipurile de date sunt prezentate în varianta logică (bigint, varchar, date, decimal) — maparea la tipurile fizice Oracle (`NUMBER(19)`, `VARCHAR2`, `DATE`, `NUMBER(p,s)`) se face în implementarea backend-ului.

![Schema conceptuală OLTP globală](build/02-conceptual-global.png){#fig:conceptual width=100%}

Cele mai relevante observații, din perspectiva fragmentării ulterioare:

1. `FISE_CLIENTI.moneda` are cardinalitate redusă (4 valori distincte în volumul efectiv: RON, EUR, CZK, USD) și o distribuție concentrată — peste 75% dintre documente sunt în RON. Acest fapt este premisă pentru fragmentarea orizontală primară din capitolul 4.
2. `MS_ITEMS` conține 15 atribute, dintre care un grup clar identifică produsul (cod, nume, branduri, categorii) și altul descrie aspectele comerciale-fizice (cost, greutate, barcode, furnizor). Această dihotomie va susține algoritmul de fragmentare verticală.
3. Cheia compusă `(nr_document, doc_type_xrp)` între `FISE_CLIENTI` și `LINII_DOC` este premisa fragmentării orizontale derivate: orice fragmentare a documentelor se propagă natural asupra liniilor lor.

## 2.3. Justificarea normalizării (Forma Normală 3)

Modelul respectă FN3 prin cele trei condiții cumulative:

**FN1 — atomicitate**. Toate atributele sunt atomice. Nu există coloane multi-valor sau structuri repetitive în interiorul unei celule.

**FN2 — eliminarea dependențelor parțiale**. Toate tabelele au chei primare simple (un singur atribut `id`), cu o singură excepție: `INTERVALE_PLATA_ZILE` are cheie compusă `(id_interval, per_zile)`. În acest caz, atributele non-cheie (`zile_start`, `zile_end`) depind de combinația completă a cheii, nu doar de o componentă — așadar FN2 este satisfăcută.

**FN3 — eliminarea dependențelor tranzitive**. Niciun atribut non-cheie nu depinde de un alt atribut non-cheie. De exemplu, în `CLIENTI`, atributul `denumire_client` depinde direct de cheia primară `id`, nu de un atribut intermediar. O potențială violare ar fi fost păstrarea zonei clientului în tabela `FISE_CLIENTI` (dependență tranzitivă `id` → `cod_client` → `id_zona`); am evitat acest design prin păstrarea în `FISE_CLIENTI` doar a `cod_client`, urmând ca informația despre zonă să fie obținută prin join.

Modelul rezultat este normalizat la FN3 și permite fragmentări corecte (completitudine, reconstrucție, disjuncție — verificate în capitolul 5).

# 3. Modul de distribuire a datelor

Arhitectura distribuită folosește trei servere logice de baze de date, implementate ca trei Pluggable Databases (PDB-uri) într-un singur Container Database (CDB) Oracle 21c Express Edition. Alegerea acestei configurări (în loc de trei instanțe Oracle separate) este motivată de două argumente: (1) Oracle 21c XE suportă maxim trei PDB-uri în varianta gratuită, ceea ce se aliniază natural cu necesitatea proiectului, și (2) izolarea logică între PDB-uri este completă (utilizatori, tablespaces, database links, materialized views) — fiecare PDB se comportă ca o bază de date independentă, fără a duplica costul de instanță Oracle.

Cele trei noduri sunt:

- `DISTRIBUTIE` — schema utilizator `SGBD_DISTRIBUTIE`, găzduiește 8 tabele master cu volume mici (52 de rânduri în total): clienții, agenții, zonele, contactele, termenele de plată și cele două relații M:N (`ZONE_AGENTI`, `ZONE_INTERVALE_PLATA`).
- `CATALOG` — schema `SGBD_CATALOG`, găzduiește catalogul de produse fragmentat vertical (`ITEMS_CORE` + `ITEMS_EXTRA`) plus cele 4 tabele lookup (`BRANDS`, `ITEMS_CATEGORY`, `ITEMS_TYPE`, `ITEMS_SEASONS`). Volum total: 6.550 de rânduri.
- `VANZARI` — schema `SGBD_VANZARI`, găzduiește fact tables-urile fragmentate orizontal (`FISE_CLIENTI_RO`, `FISE_CLIENTI_EXT`, `LINII_DOC_RO`, `LINII_DOC_EXT`) plus 7 materialized views replicate pentru join-uri locale. Volum în fragmente: 7.566 de rânduri.

![Topologia rețelei distribuite](build/03-distributie-topologie.png){#fig:topologie width=85%}

Topologia este în stea, cu `VANZARI` în rol de consumator: nodul de tranzacții inițiază două database links (`lnk_distributie` și `lnk_catalog`) către celelalte două PDB-uri pentru a accesa datele master. Replicarea datelor master în `VANZARI` se face prin materialized views cu refresh FAST în mod ON DEMAND, declanșate periodic (interval 60 secunde) printr-un job DBMS_SCHEDULER. Această decizie ocolește o limitare a Oracle: opțiunea `REFRESH ON COMMIT` nu este disponibilă cross-PDB.

Aplicația-client se conectează la `VANZARI` și operează asupra view-urilor de transparență (`V_FISE_CLIENTI`, `V_LINII_DOC`, `V_ITEMS` care e local în `CATALOG` dar replicat) și a MV-urilor. Pentru operațiile de scriere, triggere `INSTEAD OF` rutează insert-urile către fragmentul corect pe baza valorii predicatului de fragmentare (de exemplu, `moneda = 'RON'` → `FISE_CLIENTI_RO`).

# 4. Argumentarea deciziei de fragmentare

Decizia de fragmentare urmează trei criterii: (1) maximizarea local-ității de acces pentru workload-ul dominant, (2) reducerea volumului transferat pe rețea în query-urile distribuite, (3) coerența semantică între fragmente și unitățile de business reprezentate. Aplicăm trei tehnici: fragmentare orizontală primară (pe `FISE_CLIENTI`), fragmentare orizontală derivată (pe `LINII_DOC`) și fragmentare verticală pe `MS_ITEMS`.

## 4.1. Fragmentare orizontală primară pe FISE_CLIENTI

### 4.1.1. Workload și predicate candidate

Volumul observat în datele reale arată că documentele se grupează natural pe două dimensiuni candidate pentru fragmentare: anul calendaristic și moneda. Distribuția aproximativă în setul de 2.048 de documente este:

| Dimensiune | Valori distincte | Distribuție (aproximativă) |
|---|---|---|
| `data_doc_efectiva` (an) | 2021, 2022, 2023, 2024, 2025, 2026 | relativ uniformă pe ultimii 4 ani |
| `moneda` | RON, EUR, CZK, USD | ~76% RON, ~24% non-RON (EUR + CZK + rar USD) |

Fragmentarea pe an ar produce 6 fragmente, dintre care două (2021, 2026) au volum mic — pattern neuniform. Mai grav, criteriul anului nu se corelează cu nicio decizie de business (toate zonele scriu documente în toți anii).

Fragmentarea pe monedă, în schimb, se corelează cu un criteriu geografic puternic: documentele în RON aparțin în proporție covârșitoare zonelor interne (ARDEAL, MOLDOVA, SUD), iar cele în EUR/CZK aparțin zonelor externe (SLOVACIA, CEHIA). Aceasta face fragmentarea pe monedă atât eficientă tehnic (volume echilibrate ~3:1), cât și semnificativă semantic.

### 4.1.2. Aplicarea algoritmului COM_MIN

Algoritmul COM_MIN identifică un set minim și complet de predicate pentru fragmentare, pornind de la predicatele simple candidate. Mulțimea inițială:

$$\mathit{Pr} = \{p_1: \texttt{moneda} = \text{'RON'},\ p_2: \texttt{moneda} = \text{'EUR'},\ p_3: \texttt{moneda} = \text{'CZK'},\ p_4: \texttt{moneda} = \text{'USD'}\}$$

**Pasul 1 — Test de relevanță**. Un predicat $p_i$ este relevant dacă există un acces la datele filtrate de $p_i$ care răspunde diferit de cel filtrat de $\neg p_i$. Pentru $p_1$: workload-ul de raportare per zonă filtrează documentele RON (operațiuni domestice) separat de cele non-RON (operațiuni externe). Diferența numerică este semnificativă (~1555 vs. ~493 de documente), iar predicatul devine util pentru a co-localiza documentele cu zonele corespunzătoare. Aceeași logică validează relevanța lui $p_2$, $p_3$.

Predicatul $p_4$ (`moneda = 'USD'`) are mai puțin de 1% din volum și nu apare ca filtru frecvent în workload-ul real. Îl considerăm marginal — îl absorbim în clusterul „non-RON" împreună cu EUR și CZK.

**Pasul 2 — Test de completitudine**. Un set de predicate este complet dacă reuniunea lor acoperă întreg domeniul. Verificare empirică:

```sql
SELECT DISTINCT moneda FROM fise_clienti;
-- returnează exact 4 valori: RON, EUR, CZK, USD
```

Predicatele $p_1 \vee p_2 \vee p_3 \vee p_4$ acoperă întreg domeniul `moneda` ⇒ set complet.

**Pasul 3 — Minimalitate și simplificare**. Setul $\{p_1, p_2, p_3, p_4\}$ este minimal (fără redundanță), dar generează 4 fragmente. Aplicând criteriul de coerență geografică (RO domestic vs. extern), fuzionăm $p_2$, $p_3$, $p_4$ într-un singur predicat compus „non-RON". Această fuziune este o decizie de design care simplifică modelul în detrimentul granularității — argumentată prin faptul că tehnicile de optimizare ulterioare (raportarea per țară) pot folosi filtre suplimentare în interiorul fragmentului non-RON, fără să justifice fragmente fizice separate pentru EUR, CZK și USD.

Setul final de predicate compuse minimale și complete:

$$M = \{m_1: \texttt{moneda} = \text{'RON'},\ m_2: \texttt{moneda} \neq \text{'RON'}\}$$

### 4.1.3. Fragmentele orizontale primare obținute

$$\mathit{FISE\_CLIENTI\_RO} = \sigma_{\texttt{moneda}='RON'}(\mathit{FISE\_CLIENTI})$$
$$\mathit{FISE\_CLIENTI\_EXT} = \sigma_{\texttt{moneda} \neq 'RON'}(\mathit{FISE\_CLIENTI})$$

Volume efective după split: 1.555 documente în `FISE_CLIENTI_RO`, 493 în `FISE_CLIENTI_EXT` (total 2.048). Fragmentele se stochează în nodul `VANZARI` și se accesează unitar prin view-ul `V_FISE_CLIENTI = FISE_CLIENTI_RO UNION ALL FISE_CLIENTI_EXT`.

## 4.2. Fragmentare orizontală derivată pe LINII_DOC

### 4.2.1. Legătura între relații prin cheie compusă

`LINII_DOC` este o relație member al cărei owner este `FISE_CLIENTI` — fiecare linie aparține unui și numai unui document, iar legătura se realizează prin cheia externă compusă $(nr\_document, doc\_type\_xrp)$. Întrucât owner-ul este deja fragmentat orizontal, este natural ca member-ul să-l urmeze (fragmentare derivată), pentru a evita join-uri cross-fragment costisitoare.

Graful de fragmentare este simplu: fiecare linie are exact un header. Această condiție este necesară pentru ca disjuncția fragmentelor derivate să fie automată — niciun tuplu de linie nu poate aparține simultan la două fragmente diferite.

### 4.2.2. Fragmentele orizontale derivate obținute

Aplicăm operatorul de semijoin față de cele două fragmente ale owner-ului:

$$\mathit{LINII\_DOC\_RO} = \mathit{LINII\_DOC} \ltimes \mathit{FISE\_CLIENTI\_RO}$$
$$\mathit{LINII\_DOC\_EXT} = \mathit{LINII\_DOC} \ltimes \mathit{FISE\_CLIENTI\_EXT}$$

Semijoin-ul propagă criteriul de selecție de la owner la member fără a duplica atribute. Volumele efective: 3.806 linii în `LINII_DOC_RO`, 1.712 în `LINII_DOC_EXT` (total 5.518 — din 5.598 inițiale au fost eliminate 80 linii orfane, adică linii al căror `item_code` nu mai avea corespondent în `MS_ITEMS` în setul de date selectat; eliminarea s-a făcut la enforcement-ul cheii externe către `MV_ITEMS_CORE`).

Fragmentele se stochează tot în nodul `VANZARI` și se accesează unitar prin view-ul `V_LINII_DOC = LINII_DOC_RO UNION ALL LINII_DOC_EXT`. Cheia externă către owner se păstrează intra-fragment (`LINII_DOC_RO` referențiază `FISE_CLIENTI_RO`, `LINII_DOC_EXT` referențiază `FISE_CLIENTI_EXT`), ceea ce permite Oracle să optimizeze join-urile prin partition-wise execution natural.

## 4.3. Fragmentare verticală pe ITEMS (algoritmul BEA)

### 4.3.1. Workload și matricea de utilizare a atributelor

Tabela `MS_ITEMS` are 15 atribute, dintre care `id` (cheia primară) va fi replicat în ambele fragmente pentru a permite reconstrucția prin join. Restul de 14 atribute sunt candidate pentru BEA.

Pentru aplicarea algoritmului avem nevoie de un workload reprezentativ. Cinci tipuri de query-uri reprezintă cazurile dominante:

| Cod | Aplicație | Frecvență (acc/lună) |
|---|---|---|
| $q_1$ | Catalog browse — agenții consultă produsele cu identificare și clasificare | 25 |
| $q_2$ | Insert linie factură — necesită `item_code` și `item_name` pentru validare | 85 |
| $q_3$ | Raport top vânzări (lunar) — agregare pe categorie | 1 |
| $q_4$ | Editare fișă produs (admin) — descriere, TVA, barcode, greutate, UM | 25 |
| $q_5$ | Update cost & furnizor (per produs) — cost și cod furnizor | 30 |

Frecvențele sunt derivate empiric din volumul real (5.598 linii într-o perioadă de 66 de luni dă o medie de ~85 inserări/lună) și completate cu estimări pentru workload-ul de gestiune.

Matricea de utilizare $VA$ (1 dacă atributul este accesat de query, 0 altfel). Notăm atributele non-cheie cu indici $A_1$..$A_{14}$ în ordinea: `item_code`, `item_name`, `item_description`, `brand_id`, `season_id`, `item_type_id`, `category_id`, `active`, `vat`, `last_cost_price`, `main_barcode`, `supplier_code`, `weight`, `um`.

|       | $A_1$ | $A_2$ | $A_3$ | $A_4$ | $A_5$ | $A_6$ | $A_7$ | $A_8$ | $A_9$ | $A_{10}$ | $A_{11}$ | $A_{12}$ | $A_{13}$ | $A_{14}$ |
|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|----------|----------|----------|----------|----------|
| $q_1$ | 1     | 1     | 0     | 1     | 1     | 1     | 1     | 1     | 0     | 0        | 0        | 0        | 0        | 0        |
| $q_2$ | 1     | 1     | 0     | 0     | 0     | 0     | 0     | 0     | 0     | 0        | 0        | 0        | 0        | 0        |
| $q_3$ | 1     | 1     | 0     | 0     | 0     | 0     | 1     | 0     | 0     | 0        | 0        | 0        | 0        | 0        |
| $q_4$ | 0     | 1     | 1     | 0     | 0     | 0     | 0     | 0     | 1     | 0        | 1        | 0        | 1        | 1        |
| $q_5$ | 0     | 0     | 0     | 0     | 0     | 0     | 0     | 0     | 0     | 1        | 0        | 1        | 0        | 0        |

### 4.3.2. Aplicarea algoritmului BEA și algoritmul PART

Afinitatea între două atribute $A_i$ și $A_j$ se calculează prin formula:

$$\mathit{aff}(A_i, A_j) = \sum_{q \mid \mathit{use}(q, A_i) = \mathit{use}(q, A_j) = 1} \mathit{acc}(q)$$

Două perechi exemplificative:

**Perechea ($A_1$, $A_2$) = (item_code, item_name)**: ambele atribute sunt accesate de $q_1$, $q_2$ și $q_3$, deci:
$$\mathit{aff}(A_1, A_2) = \mathit{acc}(q_1) + \mathit{acc}(q_2) + \mathit{acc}(q_3) = 25 + 85 + 1 = 111$$
Aceasta este afinitatea maximă din toată matricea — codul și numele sunt aproape întotdeauna citite împreună.

**Perechea ($A_1$, $A_{13}$) = (item_code, weight)**: niciun query nu le accesează simultan, deci:
$$\mathit{aff}(A_1, A_{13}) = 0$$
Afinitate zero — `item_code` ține de identificare/clasificare, `weight` ține de atribute fizice administrative.

După calculul tuturor celor 91 de perechi posibile și permutarea coloanelor matricei AA (criteriu: maximizarea contribuției globale), matricea CA permutată evidențiază clar două clustere de atribute cu afinitate intra-grup ridicată și afinitate inter-grup scăzută:

- **Cluster CORE**: $\{A_1, A_2, A_4, A_5, A_6, A_7, A_8\}$ — `item_code`, `item_name`, `brand_id`, `season_id`, `item_type_id`, `category_id`, `active`
- **Cluster EXTRA**: $\{A_3, A_9, A_{10}, A_{11}, A_{12}, A_{13}, A_{14}\}$ — `item_description`, `vat`, `last_cost_price`, `main_barcode`, `supplier_code`, `weight`, `um`

Pentru a alege punctul concret de bipartiție, aplicăm algoritmul PART, care maximizează funcția obiectiv:

$$z = \mathit{CTQ} \cdot \mathit{CBQ} - \mathit{COQ}^2$$

unde $\mathit{CTQ}$ = suma frecvențelor query-urilor care accesează doar atribute din clusterul CORE, $\mathit{CBQ}$ = suma pentru clusterul EXTRA, iar $\mathit{COQ}$ = suma pentru query-urile care accesează atribute din ambele clustere. Pentru bipartiția propusă:

- $\mathit{TQ} = \{q_1, q_2, q_3\}$ — accesează doar atribute CORE → $\mathit{CTQ} = 25 + 85 + 1 = 111$
- $\mathit{BQ} = \{q_5\}$ — accesează doar atribute EXTRA → $\mathit{CBQ} = 30$
- $\mathit{OQ} = \{q_4\}$ — accesează atribute din ambele clustere → $\mathit{COQ} = 25$
- $z = 111 \times 30 - 25^2 = 3.330 - 625 = \mathbf{2.705}$ — maxim global.

### 4.3.3. Fragmentele verticale obținute

$$\mathit{ITEMS\_CORE} = \pi_{id, A_1, A_2, A_4, A_5, A_6, A_7, A_8}(\mathit{MS\_ITEMS})$$
$$\mathit{ITEMS\_EXTRA} = \pi_{id, A_3, A_9, A_{10}, A_{11}, A_{12}, A_{13}, A_{14}}(\mathit{MS\_ITEMS})$$

Cheia primară `id` este replicată în ambele fragmente pentru a permite reconstrucția prin join. Volum: 3.192 de rânduri în fiecare fragment (egale, deoarece fragmentarea verticală partiționează atribute, nu tupluri).

Fragmentele se stochează în nodul `CATALOG` și se accesează unitar prin view-ul:

```sql
CREATE OR REPLACE VIEW V_ITEMS AS
SELECT c.id, c.item_code, c.item_name, e.item_description,
       c.brand_id, c.season_id, c.item_type_id, c.category_id,
       e.vat, e.last_cost_price, e.main_barcode, e.supplier_code,
       e.weight, e.um, c.active
FROM   ITEMS_CORE c
       JOIN ITEMS_EXTRA e ON e.id = c.id;
```

Pentru operațiile DML peste view, triggere `INSTEAD OF` rutează inserările/actualizările/ștergerile către cele două fragmente.

# 5. Verificarea corectitudinii fragmentărilor

<!-- Conținut Task 13. Punctaj: 1p. -->

# 6. Argumentarea deciziei de replicare

<!-- Conținut Task 14. Punctaj: 0.5p. -->

# 7. Schemele conceptuale locale

<!-- Conținut Task 15. Punctaj: 0.75p obligatoriu. -->

## 7.1. Schema PDB DISTRIBUTIE

## 7.2. Schema PDB CATALOG

## 7.3. Schema PDB VANZARI

# 8. Constrângeri de integritate

<!-- Conținut Task 16. Punctaj: 2p obligatoriu. -->

## 8.1. Constrângeri de unicitate

## 8.2. Chei primare

## 8.3. Chei externe

## 8.4. Constrângeri de validare

# 9. Cererea SQL complexă și tehnici de optimizare

<!-- Conținut Task 17. Punctaj: 0.25p. -->

# Bibliografie și notă de transparență

<!-- Conținut Task 18. -->
