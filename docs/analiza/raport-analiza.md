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

Pentru ca o fragmentare să fie corectă, trebuie să îndeplinească trei condiții cumulative: completitudine, reconstrucție (lossless join) și disjuncție. Verificăm cele trei condiții pentru fiecare dintre cele trei fragmentări aplicate.

| Fragmentare | Completitudine | Reconstrucție | Disjuncție |
|---|---|---|---|
| Orizontală primară `FISE_CLIENTI` (pe `moneda`) | $m_1 \vee m_2 \equiv \texttt{moneda is not null}$ — verificată empiric: toate cele 2.048 documente au monedă populată | $\mathit{FISE\_CLIENTI} = \mathit{FISE\_CLIENTI\_RO} \cup \mathit{FISE\_CLIENTI\_EXT}$ (UNION ALL) — 1.555 + 493 = 2.048, identic cu populația originală | $m_1 \wedge m_2 \equiv \texttt{FALSE}$ — un tuplu cu `moneda = 'RON'` nu poate satisface `moneda <> 'RON'` |
| Orizontală derivată `LINII_DOC` (semijoin) | Cheia externă (`nr_document`, `doc_type_xrp`) este obligatorie (NOT NULL + FK enforcement) — fiecare linie are header, deci aparține unui fragment | $\mathit{LINII\_DOC} = \mathit{LINII\_DOC\_RO} \cup \mathit{LINII\_DOC\_EXT}$ — 3.806 + 1.712 = 5.518 (după eliminarea celor 80 orfani fără `item_code` valid) | Cheia primară `id` a liniei este unică global, iar fiecare linie e legată de un singur header (cardinalitate 1) — deci aparține unui singur fragment derivat |
| Verticală `MS_ITEMS` (BEA → CORE/EXTRA) | Atributele $A_1$..$A_{14}$ acoperite de reuniune: `ITEMS_CORE` are 7 + `id`, `ITEMS_EXTRA` are 7 + `id` = 14 atribute non-cheie + cheia replicată. Niciun atribut omis | $\mathit{MS\_ITEMS} = \mathit{ITEMS\_CORE} \bowtie_{id} \mathit{ITEMS\_EXTRA}$ — join pe PK garantează reconstrucție lossless (FN3 + PK obligatoriu) | Atributele disjuncte între cele două fragmente, cu excepția cheii primare `id`, care e replicată intenționat pentru join. Disjuncția pe atribute non-cheie este completă |

Verificările au fost confirmate empiric în timpul implementării prin teste de tip:

```sql
-- Reconstrucție fragmentare orizontală
SELECT COUNT(*) FROM v_fise_clienti;        -- 2.048 (corect)
SELECT COUNT(*) FROM fise_clienti_ro;       -- 1.555
SELECT COUNT(*) FROM fise_clienti_ext;      -- 493

-- Disjuncția fragmentării orizontale
SELECT COUNT(*) FROM fise_clienti_ro
WHERE moneda <> 'RON';                       -- 0 (CHECK constraint împiedică)

-- Reconstrucție fragmentare verticală
SELECT COUNT(*) FROM v_items;                -- 3.192 (corect)
SELECT COUNT(*) FROM items_core c
WHERE NOT EXISTS (SELECT 1 FROM items_extra e WHERE e.id = c.id);  -- 0 (FK obligatoriu)
```

Constrângerile CHECK pe predicatele de fragmentare (`ck_fise_ro_mon: moneda = 'RON'`, `ck_fise_ext_mon: moneda <> 'RON'`) garantează la nivel de bază de date că orice insert sau update respectă disjuncția — un document nu poate „migra accidental" în fragmentul greșit.

# 6. Argumentarea deciziei de replicare

Decizia de a replica o relație sau de a o stoca pe o singură stație urmează trei criterii principale:

1. **Volumul tabelei**. Tabele cu sub ~10.000 de rânduri pot fi replicate cu cost de stocare neglijabil. Pentru tabele mari (fact tables cu sute de mii sau milioane de rânduri), replicarea devine prohibitivă în spațiu și în timp de sincronizare.
2. **Raportul citire/scriere**. Tabele cu citire frecventă și scriere rară (tipice pentru lookup-uri și date master) beneficiază maxim de replicare — cititorii locali nu mai depind de comunicarea cu nodul-master. Tabele cu scriere frecventă (fact tables) sunt slabe candidate, deoarece sincronizarea ar deveni costisitoare.
3. **Locația join-urilor**. Dacă o tabelă este join-uită frecvent cu fact tables într-un nod specific, replicarea ei în acel nod elimină hop-uri remote din planurile de execuție. Atunci când join-urile sunt mai rare sau ad-hoc, accesul prin database link cu remote scan este suficient.

Aplicarea acestor criterii produce deciziile concrete:

| Tabel | Master în | Replicat în | Justificare |
|---|---|---|---|
| `zone` | DISTRIBUTIE | VANZARI | Volum mic (5 rânduri), citită în orice raport de vânzări pe zonă. Replicarea elimină 1 hop la fiecare query. |
| `clienti` | DISTRIBUTIE | VANZARI | Volum mic (10 rânduri), FK cross-PDB din `FISE_CLIENTI` — replicarea permite enforcement local al constrângerii. |
| `items_core` | CATALOG | VANZARI | 3.192 rânduri, FK cross-PDB din `LINII_DOC` — necesar pentru enforcement local. |
| `brands` | CATALOG | VANZARI | 131 rânduri, join frecvent în rapoarte (top branduri vândute). |
| `items_category` | CATALOG | VANZARI | 15 rânduri, join obligatoriu în cererea complexă (top agenți pe categorie). |
| `items_type` | CATALOG | VANZARI | 3 rânduri, lookup în rapoarte sezoniere. |
| `items_seasons` | CATALOG | VANZARI | 17 rânduri, lookup în rapoarte sezoniere. |
| `items_extra` | CATALOG | nicăieri | Atribute administrative (cost, furnizor), acces strict local pentru rolul de admin produse. |
| `agenti` | DISTRIBUTIE | nicăieri | Acces ad-hoc din cererea complexă; replicarea ar avea cost de sincronizare fără beneficiu măsurabil în absența join-urilor frecvente. |
| `zone_agenti`, `zone_intervale_plata` | DISTRIBUTIE | nicăieri | Asocieri temporale M:N — accesate doar prin DB link în cererea complexă, cu predicate temporale restrictive. |
| `intervale_plata`, `intervale_plata_zile` | DISTRIBUTIE | nicăieri | Acces ad-hoc, lookup pentru calculul scadențelor. |
| `fise_clienti_*`, `linii_doc_*` | VANZARI | nicăieri | Fact tables fragmentate orizontal; volum mare, scriere intensă. Replicarea ar contraveni întregului design distribuit. |

Replicarea se implementează prin materialized views cu refresh FAST în mod ON DEMAND. Logurile de materialized view (`CREATE MATERIALIZED VIEW LOG ON tabel ...`) instalate pe tabela master capturează modificările incremental, iar refresh-ul propagă doar delta — un mecanism eficient pentru volume mici și moderate. Sincronizarea se face printr-un job DBMS_SCHEDULER cu interval de 60 de secunde, ales ca trade-off între prospețime și cost de overhead. Lag-ul maxim acceptat (60 secunde) este compatibil cu rapoartele și operațiile interactive obișnuite; pentru cazuri care necesită prospețime maximă (de exemplu, demo-uri ale propagării LMD), refresh-ul poate fi forțat manual prin `DBMS_MVIEW.REFRESH(...)`.

# 7. Schemele conceptuale locale

După fragmentare și distribuție, schema conceptuală globală se descompune în trei scheme locale, una per PDB. Schemele locale prezintă tabelele fizice (master + fragmente + materialized views), cheile primare și externe, plus view-urile de transparență.

## 7.1. Schema PDB DISTRIBUTIE

Nodul `DISTRIBUTIE` păstrează 8 tabele master fără fragmentare — toate au volum mic și sunt accesate fie local pentru CRM, fie remote prin DB link pentru join-uri în cererea complexă.

![Schema conceptuală locală — PDB DISTRIBUTIE](build/04-conceptual-distributie.png){#fig:schema-distributie width=100%}

Cheile primare sunt simple (un singur `id` per tabelă), cu excepția `INTERVALE_PLATA_ZILE` care are cheie compusă `(id_interval, per_zile)`. Cheile externe locale (intra-PDB) sunt 8: `clienti → zone`, `clienti_contacte → clienti`, `zone_agenti → zone`, `zone_agenti → agenti`, `zone_intervale_plata → zone`, `zone_intervale_plata → intervale_plata`, `intervale_plata_zile → intervale_plata`, plus auto-referință `zone → zone` (parent).

## 7.2. Schema PDB CATALOG

Nodul `CATALOG` găzduiește catalogul de produse, cu fragmentarea verticală aplicată pe `MS_ITEMS`. Cele două fragmente fizice (`ITEMS_CORE` și `ITEMS_EXTRA`) sunt expuse unitar prin view-ul `V_ITEMS`, care realizează transparența verticală — aplicația-client vede o singură tabelă logică.

![Schema conceptuală locală — PDB CATALOG](build/05-conceptual-catalog.png){#fig:schema-catalog width=100%}

`ITEMS_EXTRA` are PK = FK către `ITEMS_CORE` (relație 1:1, cu ON DELETE CASCADE), ceea ce garantează că orice produs din CORE are exact o intrare în EXTRA. Cheile externe locale sunt 4 (de la `ITEMS_CORE` către cele patru lookup-uri) plus FK-ul 1:1 între cele două fragmente.

Triggere INSTEAD OF pe `V_ITEMS` rutează inserările, actualizările și ștergerile către ambele fragmente — aplicația nu trebuie să cunoască existența split-ului vertical.

## 7.3. Schema PDB VANZARI

Nodul `VANZARI` este cel mai complex din punct de vedere structural: găzduiește 4 fragmente fizice orizontale (cele 2 fragmente de fișe × cele 2 fragmente de linii), 2 view-uri de transparență (`V_FISE_CLIENTI`, `V_LINII_DOC`) și 7 materialized views replicate din celelalte două noduri.

![Schema conceptuală locală — PDB VANZARI](build/06-conceptual-vanzari.png){#fig:schema-vanzari width=100%}

Cheile externe locale intra-PDB sunt 2: `LINII_DOC_RO → FISE_CLIENTI_RO` și `LINII_DOC_EXT → FISE_CLIENTI_EXT` (pe cheia compusă `(nr_document, doc_type_xrp)`). Cheile externe către tabelele replicate (cross-PDB la nivel logic, dar locale la nivel de Oracle deoarece referențiază MV-uri replicate) sunt 4:

- `FISE_CLIENTI_RO.cod_client → MV_CLIENTI.cod_client`
- `FISE_CLIENTI_EXT.cod_client → MV_CLIENTI.cod_client`
- `LINII_DOC_RO.item_code → MV_ITEMS_CORE.item_code`
- `LINII_DOC_EXT.item_code → MV_ITEMS_CORE.item_code`

Triggere INSTEAD OF pe `V_FISE_CLIENTI` și `V_LINII_DOC` rutează DML-ul către fragmentele corecte pe baza predicatului de fragmentare (`moneda` pentru fișe). Aplicația-client lucrează exclusiv cu view-urile — fragmentarea orizontală este complet ascunsă.

# 8. Constrângeri de integritate

Constrângerile de integritate acoperă patru categorii: unicitate, chei primare, chei externe și validări semantice. Pentru fiecare, distingem între nivelul local (intra-PDB) și nivelul global (cross-PDB).

## 8.1. Constrângeri de unicitate

### 8.1.1. Unicitate locală

Fiecare PDB are propriile constrângeri UK pentru atributele care identifică o entitate dincolo de cheia surogat numerică:

| PDB | Tabel | UK |
|---|---|---|
| DISTRIBUTIE | `zone` | `cod_zona` |
| DISTRIBUTIE | `agenti` | `cod_agent` |
| DISTRIBUTIE | `clienti` | `cod_client` |
| DISTRIBUTIE | `intervale_plata` | `den_interval` |
| CATALOG | `brands` | `code` |
| CATALOG | `items_category` | `code` |
| CATALOG | `items_type` | `code` |
| CATALOG | `items_seasons` | `code` |
| CATALOG | `items_core` | `item_code` |
| VANZARI | `fise_clienti_ro` | `(nr_document, doc_type_xrp)` |
| VANZARI | `fise_clienti_ext` | `(nr_document, doc_type_xrp)` |

### 8.1.2. Unicitate globală pe fragmente orizontale

Pentru o relație fragmentată orizontal, cheia logică trebuie să rămână unică la nivel global, nu doar în interiorul fragmentului. Pentru `FISE_CLIENTI`, cheia logică este `(nr_document, doc_type_xrp)` și trebuie să fie unică între `FISE_CLIENTI_RO` și `FISE_CLIENTI_EXT`.

Această unicitate globală este asigurată implicit prin construcție: predicatele de fragmentare sunt disjuncte (`moneda = 'RON'` ⊥ `moneda <> 'RON'`), deci un tuplu cu o anumită cheie logică nu poate exista simultan în ambele fragmente. Coroborat cu UK locală în fiecare fragment, cheia logică globală este unică prin design.

Aceeași logică se aplică pentru `LINII_DOC` — cheia primară `id` este unică în fiecare fragment (`LINII_DOC_RO`, `LINII_DOC_EXT`), iar o linie aparține unui singur fragment (urmează owner-ul prin semijoin).

### 8.1.3. Unicitate globală pe fragmente verticale

Pentru fragmentarea verticală a `MS_ITEMS`, problema de unicitate are altă natură: atributul de identificare a produsului (`item_code`) trebuie să rămână unic global. Acest atribut este însă plasat doar în fragmentul `ITEMS_CORE` (nu este replicat în `ITEMS_EXTRA`), deci unicitatea sa locală în CORE este și globală.

Cheia primară surogat `id` este replicată în ambele fragmente pentru a permite reconstrucția. Pentru a asigura că un anumit `id` nu există fără pereche în ambele fragmente, am definit FK-ul `ITEMS_EXTRA.id → ITEMS_CORE.id ON DELETE CASCADE`, care garantează corespondența 1:1 între fragmente.

## 8.2. Chei primare

### 8.2.1. La nivel local

Toate tabelele au cheie primară definită explicit prin constrângere `PRIMARY KEY` la create-time. În toate cazurile cu o singură excepție, PK-ul este un atribut surogat numeric (`id NUMBER(19)`). Excepția este `INTERVALE_PLATA_ZILE`, care folosește PK compus `(id_interval, per_zile)` — atributele cheii sunt semnificative din punct de vedere business (un interval poate avea mai multe perioade de zile distincte, fiecare cu propria denumire).

Pentru `CLIENTI_CONTACTE`, PK-ul `cod_client` este simultan și FK către `CLIENTI.cod_client` — relație 1:1 strictă (un client are un singur contact).

### 8.2.2. La nivel global pe fragmente orizontale

Pentru `FISE_CLIENTI` reconstituit prin `V_FISE_CLIENTI`, cheia primară globală este `id` — unic în fiecare fragment și unic global prin convenția de generare a ID-urilor (secvențe care nu se suprapun). Acest invariant este menținut aplicativ; o verificare suplimentară poate fi adăugată ca trigger global care interzice insert-uri cu `id` deja prezent în fragmentul opus (acceptabil pentru volumul implicat).

Pentru `LINII_DOC` reconstituit prin `V_LINII_DOC`, cheia primară globală `id` este unică prin construcție (semijoin-ul nu duplică tupluri).

Pentru `MS_ITEMS` reconstituit prin `V_ITEMS`, cheia primară globală este `id` — unică în `ITEMS_CORE` (UK local), și replicată în `ITEMS_EXTRA` prin FK.

## 8.3. Chei externe

### 8.3.1. La nivel local (intra-PDB)

| PDB | FK | Referință |
|---|---|---|
| DISTRIBUTIE | `clienti.id_zona` | `zone.id` |
| DISTRIBUTIE | `clienti_contacte.cod_client` | `clienti.cod_client` |
| DISTRIBUTIE | `zone_agenti.id_zona` | `zone.id` |
| DISTRIBUTIE | `zone_agenti.id_agent` | `agenti.id` |
| DISTRIBUTIE | `zone_intervale_plata.id_zona` | `zone.id` |
| DISTRIBUTIE | `zone_intervale_plata.id_interval` | `intervale_plata.id` |
| DISTRIBUTIE | `intervale_plata_zile.id_interval` | `intervale_plata.id` |
| DISTRIBUTIE | `zone.parent_zona_id` (self-FK) | `zone.id` |
| CATALOG | `items_core.brand_id` | `brands.id` |
| CATALOG | `items_core.season_id` | `items_seasons.id` |
| CATALOG | `items_core.item_type_id` | `items_type.id` |
| CATALOG | `items_core.category_id` | `items_category.id` |
| CATALOG | `items_extra.id` (PK = FK) | `items_core.id` ON DELETE CASCADE |
| VANZARI | `linii_doc_ro.(nr_document, doc_type_xrp)` | `fise_clienti_ro.(nr_document, doc_type_xrp)` |
| VANZARI | `linii_doc_ext.(nr_document, doc_type_xrp)` | `fise_clienti_ext.(nr_document, doc_type_xrp)` |

### 8.3.2. Pentru relații stocate în baze de date diferite

Cheile externe cross-PDB nu pot fi declarate direct între tabele din PDB-uri diferite (limitare Oracle). Soluția adoptată: replicăm tabelele referențiate ca materialized views în PDB-ul referențiator și definim FK-urile către aceste MV-uri. Sincronizarea MV-urilor (job @ 60s) garantează că enforcement-ul FK reflectă starea master cu un lag controlat.

Cele 4 FK-uri cross-PDB implementate:

| FK | Referință (master) | Reference locală (MV) |
|---|---|---|
| `fise_clienti_ro.cod_client` | `clienti@DISTRIBUTIE.cod_client` | `mv_clienti.cod_client` |
| `fise_clienti_ext.cod_client` | `clienti@DISTRIBUTIE.cod_client` | `mv_clienti.cod_client` |
| `linii_doc_ro.item_code` | `items_core@CATALOG.item_code` | `mv_items_core.item_code` |
| `linii_doc_ext.item_code` | `items_core@CATALOG.item_code` | `mv_items_core.item_code` |

Trade-off-ul acceptat: până la refresh-ul MV-ului (max 60 secunde după un INSERT în master), un INSERT în VANZARI care referențiază un cod nou ar putea eșua tranzitoriu. Pentru cazurile critice, se forțează refresh manual înainte de operațiunea dependentă.

## 8.4. Constrângeri de validare

### 8.4.1. La nivel local

CHECK-uri pe domenii și pe combinații logice de atribute:

| Tabel | Constrângere | Semnificație |
|---|---|---|
| `fise_clienti_*` | `tip_doc IN ('F','I')` | Documentul este factură sau încasare |
| `fise_clienti_*` | `doc_type_xrp IN ('INV','PMT','CRM','PPM','REF','RPM','DRM','VRF')` | Tip XRP în mulțimea de coduri permise |
| `fise_clienti_*` | `semn IN (-1, 1)` | Direcția contabilă |
| `fise_clienti_ro` | `moneda = 'RON'` | Predicat de fragmentare |
| `fise_clienti_ext` | `moneda <> 'RON'` | Predicat de fragmentare |
| `items_seasons` | `active IN (0, 1)` | Boolean flag |
| `clienti` | `end_date IS NULL OR end_date > start_date` | Interval temporal valid |
| `zone_agenti` | `end_date IS NULL OR end_date > start_date` | Interval temporal valid |
| `zone_intervale_plata` | `end_date IS NULL OR end_date > start_date` | Interval temporal valid |

CHECK-urile pe predicatele de fragmentare (`ck_fise_ro_mon`, `ck_fise_ext_mon`) au un rol dublu: definesc semantica fragmentului și împiedică inserturi „pe fragmentul greșit", indiferent de calea de acces (direct sau prin view-ul de transparență).

### 8.4.2. Pentru relații stocate în baze de date diferite

Validările cross-PDB se implementează prin triggere care fac join-uri remote sau prin agregate calculate post-INSERT. Cazul concret implementat: **coerența între suma documentului și suma liniilor lui**.

Pentru fiecare document din `FISE_CLIENTI_*`, valoarea totală (`amount_doc`) trebuie să fie aproximativ egală cu suma valorilor liniilor (`SUM(xrp_linie_valoare_fara_tva + xrp_linie_tva)` peste `LINII_DOC_*` cu același `(nr_document, doc_type_xrp)`). Toleranța acceptată este 0.01 RON (eroare de rotunjire la împărțirea TVA-ului).

Implementarea este un trigger `AFTER INSERT OR UPDATE OR DELETE ON linii_doc_*` care recalculează agregatul după fiecare modificare și ridică `RAISE_APPLICATION_ERROR` dacă diferența depășește toleranța:

```sql
CREATE OR REPLACE TRIGGER trg_coerenta_sum_ro
AFTER INSERT OR UPDATE OR DELETE ON linii_doc_ro
DECLARE
  CURSOR c IS
    SELECT f.nr_document, f.doc_type_xrp,
           f.amount_doc AS doc_total,
           SUM(l.xrp_linie_valoare_fara_tva + l.xrp_linie_tva) AS sum_linii
    FROM fise_clienti_ro f
         JOIN linii_doc_ro l ON (l.nr_document, l.doc_type_xrp) = (f.nr_document, f.doc_type_xrp)
    GROUP BY f.nr_document, f.doc_type_xrp, f.amount_doc
    HAVING ABS(f.amount_doc - SUM(l.xrp_linie_valoare_fara_tva + l.xrp_linie_tva)) > 0.01;
BEGIN
  FOR r IN c LOOP
    RAISE_APPLICATION_ERROR(-20001, 'Incoerenta suma pe ' || r.nr_document || '/' || r.doc_type_xrp);
  END LOOP;
END;
/
```

Un trigger similar (`trg_coerenta_sum_ext`) acoperă fragmentul EXT.

# 9. Cererea SQL complexă și tehnici de optimizare

Pentru a demonstra valoarea modelului distribuit, am formulat o cerere SQL complexă care implică toate cele 3 PDB-uri și care va fi optimizată în modulul de implementare backend.

**Enunț în limbaj natural**:
*Care sunt cei 10 agenți cu cea mai mare valoare totală vândută în anul 2024, defalcată pe zonă comercială și categorie de produs, luând în calcul doar facturile efective (`tip_doc = 'F'`)?*

Cererea folosește simultan: agenții și asocierea zone–agenți (din `DISTRIBUTIE`, accesate prin DB link), documentele și liniile lor (din `VANZARI`, prin view-urile de transparență), zonele și categoriile de produs (replicate ca MV-uri în `VANZARI`). Implică un join de 8 relații și două agregări (suma valorilor pe combinație agent–zonă–categorie, urmată de un Top-N).

**Formularea SQL**:

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

**Tehnici de optimizare candidate**:

| Tehnică | Avantaje | Dezavantaje |
|---|---|---|
| **Optimizator bazat pe regulă (RBO)** | Predictibil, nu necesită statistici. Aplicabil când statisticile lipsesc sau sunt depășite. | Ignoră selectivitățile reale; alege deseori ordine de join suboptimală în query-uri distribuite. |
| **Optimizator bazat pe cost (CBO)** | Folosește statistici (cardinalități, distribuții) pentru a alege ordinea de join și algoritmii (nested loops vs. hash) optim. | Necesită `DBMS_STATS` proaspăt. Pe MV-uri replicate, estimările pot fi imprecise dacă statisticile nu sunt regenerate după refresh. |
| **Partition pruning pe predicate de fragmentare** | Reduce I/O drastic — predicate care coincid cu predicatul de fragmentare scanează doar fragmentul relevant (de exemplu, `moneda = 'RON'` → doar `FISE_CLIENTI_RO`). | Se aplică automat doar dacă predicatul este detectabil de optimizer; necesită view-uri scrise cu UNION ALL, nu UNION distinct. |
| **Indexare selectivă** | Indecși pe coloanele cele mai filtrate (`data_doc_efectiva`, `cod_client`, `tip_doc`) accelerează scan-urile range și join-urile. | Cost de menținere la INSERT/UPDATE; trebuie balansat cu workload-ul real. |
| **Hint `DRIVING_SITE`** | Forțează asamblarea rezultatului într-un nod specific, util când optimizer-ul nu alege site-ul cu cel mai mic volum de date transferat. | Decizie manuală; riscă să devină greșit la schimbarea volumelor. |
| **Materialized View cu query rewrite** | Pre-calculează agregările frecvente (de exemplu, total per agent–zonă–lună); optimizer-ul poate rescrie query-ul să citească din MV. | Necesită refresh periodic; potențial date stale. |
| **Semijoin pentru relații remote mici** | Reduce volumul transferat pe rețea — în loc să transferăm întreaga relație remote, transferăm doar cheile filtrului. | Adaugă o etapă suplimentară de comunicare; benefică doar când relația remote este mare și filtrul reduce semnificativ volumul. |

Compararea concretă a planurilor de execuție (RBO vs. CBO vs. DRIVING_SITE), cu costuri și timpii observați, este detaliată în raportul modulului de implementare backend.

# Bibliografie și notă de transparență

<!-- Conținut Task 18. -->
