---
title: "Proiect MODBD --- Bază de Date Distribuită pentru Distribuție B2B"
subtitle: "Modulele 1, 2 și 3 integrate"
author: "Echipa SOP --- Ștefan Măgureanu, Octavian Oprinoiu, Andrei Pițoiu"
date: "2026-05-18"
lang: ro-RO
documentclass: article
geometry: margin=2.5cm
fontsize: 12pt
mainfont: "Times New Roman"
linestretch: 1.15
---

# Notă introductivă

Acest document integrează toate cerințele proiectului MODBD (Metode de Optimizare și Distribuire în Baze de Date), conform baremul oficial publicat de coordonatorul disciplinei. Documentul este împărțit în patru părți:

- **Partea I --- Raport de Analiză** (Modulul 1): preluat integral din raportul de analiză al echipei.
- **Partea II --- Implementarea bazei de date** (Modulul 2): cod SQL/PL-SQL inline + capturi de ecran care demonstrează rularea în Oracle.
- **Partea III --- Aplicația front-end** (Modulul 3): arhitectura aplicației + capturi de ecran din interfață.
- **Partea IV --- Anexe**: componența echipei + distribuția task-urilor, codul sursă consolidat, nota de transparență AI.

\newpage

# PARTEA I --- RAPORT DE ANALIZĂ (MODULUL 1)
# Descrierea modelului și obiectivele aplicației

Aplicația proiectată gestionează activitatea unei rețele de distribuție business-to-business în domeniul fashion - încălțăminte și articole vestimentare - cu acoperire pe trei piețe: România (zonele ARDEAL, MOLDOVA, SUD), Slovacia și Cehia. Sursa datelor este o bază OLTP din mediul SQL Server (numită `Integration`, cu aproximativ 280 de tabele), din care am izolat un subset coerent: 12 entități independente și 3 relații many-to-many, în total 15 tabele cu 95 de coloane păstrate din 202 inițiale.

Selecția subsetului a urmărit două obiective. Pe de o parte, păstrarea integrității modelului relațional (toate cheile externe explicite, normalizare în Forma Normală 3). Pe de altă parte, asigurarea unui volum suficient pentru a argumenta concret deciziile de fragmentare: 10 clienți anonimizați (codurile CLI000001 până la CLI000010) acoperă cele 5 zone, 3 valute (RON, EUR, CZK), 6 ani de istoric (2021--2026) și 7 dintre cele 8 tipuri de documente - facturi, încasări, note de credit, plăți pe avans, refuzuri, retururi de plată și note de debit. În cifre brute, volumul rezultat este: 2.048 fișe de documente (header), 5.598 linii de document, 3.192 produse distincte, 131 de branduri și 17 sezoane.

Obiectivul tehnic al distribuției este descompunerea acestui model OLTP unitar într-o arhitectură cu trei noduri logice, fiecare cu o responsabilitate funcțională distinctă:

- **Nodul CRM/Comercial** -clienții, agenții, zonele și termenele de plată. Concentrează cele două dintre cele trei relații many-to-many (`ZONE_AGENTI` și `ZONE_INTERVALE_PLATA`).
- **Nodul Catalog** -produsele și clasificările lor (branduri, categorii, tipuri, sezoane). Susține fragmentare verticală pentru separarea atributelor de identificare (catalog browse) de cele administrative (cost, furnizor, dimensiuni).
- **Nodul Vânzări** -fact tables-urile de tranzacții (fișe de documente și liniile lor), fragmentate orizontal după criteriu monedă (RON vs. valute externe), aliniat cu argumentul geografic domestic/extern.

Aplicația - client va opera asupra unei vederi globale care ascunde fragmentarea: orice document poate fi consultat sau introdus prin view-uri unificate, indiferent de moneda sau locația fizică a fragmentului. La nivel fizic, fragmentele se sincronizează prin materialized views și se conectează prin database links între PDB-uri.

Pe parcursul pregătirii subsetului, am luat câteva decizii punctuale care merită menționate explicit. În primul rând, am redenumit coloana `CLS_CLASS` (denumire tehnică din sistemul ORS) ca `CATEGORY_ID` la export, pentru a evidenția faptul că este o cheie externă către tabela de categorii. În al doilea rând, am redenumit `YEAR` (sezoane) în `SEASON_YEAR`, pentru că `YEAR` este cuvânt rezervat în Oracle. În al treilea rând, am eliminat coloanele `CodLocatieClient` și `DenumireLocatieClient` din tabela de documente, deoarece anonimizarea în paralel a două coloane poate dubla numărul de rânduri.

Pentru protecția datelor cu caracter personal, codurile reale de client (numere cu 9 cifre) au fost înlocuite determinist cu identificatori fictivi CLI000001..CLI000010, iar numele clienților și ale agenților au fost generate ca șiruri sintetice. Operațiunea de anonimizare a fost asistată de un sistem AI pentru aplicarea consistentă a mapping-ului în toate cele 15 fișiere CSV.

# 2. Diagramele bazei de date OLTP inițiale

Modelul de pornire este OLTP-ul care servește operațiile zilnice ale rețelei de distribuție. Diagramele de mai jos surprind două nivele de detaliu: diagrama entitate--relație, care evidențiază entitățile, asocierile și cardinalitățile, și diagrama conceptuală detaliată, care adaugă atributele și cheile externe.

## 2.1 Diagrama Entitate--Relație

Modelul conține 12 entități independente și 3 relații many-to-many, depășind pragul minim de 10 entități cerut prin baremul oficial.

![](build/proiect/media-partea1/media/image2.svg){width="6.531944444444444in" height="4.247222222222222in"}

Diagrama Entitate--Relație OLTP

Entitățile independente sunt: `CLIENTI`, `ZONE`, `AGENTI`, `INTERVALE_PLATA`, `INTERVALE_PLATA_ZILE`, `CLIENTI_CONTACTE`, `FISE_CLIENTI`, `MS_ITEMS`, `BRANDS`, `ITEMS_CATEGORY`, `ITEMS_TYPE`, `ITEMS_SEASONS`. Relațiile many-to-many sunt:

- `ZONE_AGENTI` - un agent acoperă mai multe zone în timp, iar o zonă este acoperită succesiv de mai mulți agenți. Asocierea poartă atribute temporale (`start_date`, `end_date`) care permit reconstituirea acoperirii la o dată dată.
- `ZONE_INTERVALE_PLATA` - același pattern temporal pentru atribuirea termenelor de plată per zonă.
- `LINII_DOC` - leagă `FISE_CLIENTI` (documentele) de `MS_ITEMS` (produsele) printr-o cheie externă compusă (`nr_document`, `doc_type_xrp`) către documentul-părinte.

Tabela `ZONE` are și o auto-referință (`parent_zona_id`), care modelează ierarhia zonelor (de exemplu, o zonă-părinte „RO" cu subzonele ARDEAL, MOLDOVA, SUD).

## 2.2 Diagrama conceptuală

Diagrama conceptuală include atributele fiecărei entități, identificarea cheilor primare și externe și cardinalitățile precise (Crow's foot). Tipurile de date sunt prezentate în varianta logică (bigint, varchar, date, decimal) -maparea la tipurile fizice Oracle (`NUMBER(19)`, `VARCHAR2`, `DATE`, `NUMBER(p,s)`) se face în implementarea backend-ului.

![](build/proiect/media-partea1/media/image4.svg){width="6.531944444444444in" height="2.8222222222222224in"}

Schema conceptuală OLTP globală

Cele mai relevante observații, din perspectiva fragmentării ulterioare:

1.  `FISE_CLIENTI.moneda` are cardinalitate redusă (4 valori distincte în volumul efectiv: RON, EUR, CZK, USD) și o distribuție concentrată -peste 75% dintre documente sunt în RON. Acest fapt este premisă pentru fragmentarea orizontală primară din capitolul 4.
2.  `MS_ITEMS` conține 15 atribute, dintre care un grup clar identifică produsul (cod, nume, branduri, categorii) și altul descrie aspectele comerciale-fizice (cost, greutate, barcode, furnizor). Această dihotomie va susține algoritmul de fragmentare verticală.
3.  Cheia compusă `(nr_document, doc_type_xrp)` între `FISE_CLIENTI` și `LINII_DOC` este premisa fragmentării orizontale derivate: orice fragmentare a documentelor se propagă natural asupra liniilor lor.

## 2.3 Justificarea normalizării (Forma Normală 3)

Modelul respectă FN3 prin cele trei condiții cumulative:

**FN1 -atomicitate**. Toate atributele sunt atomice. Nu există coloane multi-valor sau structuri repetitive în interiorul unei celule.

**FN2 -eliminarea dependențelor parțiale**. Toate tabelele au chei primare simple (un singur atribut `id`), cu o singură excepție: `INTERVALE_PLATA_ZILE` are cheie compusă `(id_interval, per_zile)`. În acest caz, atributele non-cheie (`zile_start`, `zile_end`) depind de combinația completă a cheii, nu doar de o componentă -așadar FN2 este satisfăcută.

**FN3 -eliminarea dependențelor tranzitive**. Niciun atribut non-cheie nu depinde de un alt atribut non-cheie. De exemplu, în `CLIENTI`, atributul `denumire_client` depinde direct de cheia primară `id`, nu de un atribut intermediar. O potențială violare ar fi fost păstrarea zonei clientului în tabela `FISE_CLIENTI` (dependență tranzitivă `id` =\> `cod_client` =\> `id_zona`); am evitat acest design prin păstrarea în `FISE_CLIENTI` doar a `cod_client`, urmând ca informația despre zonă să fie obținută prin join.

Modelul rezultat este normalizat la FN3 și permite fragmentări corecte (completitudine, reconstrucție, disjuncție -verificate în capitolul 5).

# 3. Modul de distribuire a datelor

Arhitectura distribuită folosește trei servere logice de baze de date, implementate ca trei Pluggable Databases (PDB-uri) într-un singur Container Database (CDB) Oracle 21c Express Edition. Alegerea acestei configurări (în loc de trei instanțe Oracle separate) este motivată de două argumente: (1) Oracle 21c XE suportă maxim trei PDB-uri în varianta gratuită, ceea ce se aliniază natural cu necesitatea proiectului, și (2) izolarea logică între PDB-uri este completă (utilizatori, tablespaces, database links, materialized views) - fiecare PDB se comportă ca o bază de date independentă, fără a duplica costul de instanță Oracle.

Cele trei noduri sunt:

- `DISTRIBUTIE` - schema utilizator `SGBD_DISTRIBUTIE`, găzduiește 8 tabele master cu volume mici (52 de rânduri în total): clienții, agenții, zonele, contactele, termenele de plată și cele două relații M:N (`ZONE_AGENTI`, `ZONE_INTERVALE_PLATA`).
- `CATALOG` - schema `SGBD_CATALOG`, găzduiește catalogul de produse fragmentat vertical (`ITEMS_CORE` + `ITEMS_EXTRA`) plus cele 4 tabele lookup (`BRANDS`, `ITEMS_CATEGORY`, `ITEMS_TYPE`, `ITEMS_SEASONS`). Volum total: 6.550 de rânduri.
- `VANZARI` - schema `SGBD_VANZARI`, găzduiește fact tables-urile fragmentate orizontal (`FISE_CLIENTI_RO`, `FISE_CLIENTI_EXT`, `LINII_DOC_RO`, `LINII_DOC_EXT`) plus 7 materialized views replicate pentru join-uri locale. Volum în fragmente: 7.566 de rânduri.

![Topologia rețelei distribuite](build/proiect/media-partea1/media/image5.png){width="4.958333333333333in" height="1.5260465879265093in"}

Topologia rețelei distribuite

Topologia este în stea, cu `VANZARI` în rol de consumator: nodul de tranzacții inițiază două database links (`lnk_distributie` și `lnk_catalog`) către celelalte două PDB-uri pentru a accesa datele master. Replicarea datelor master în `VANZARI` se face prin materialized views cu refresh FAST în mod ON DEMAND, declanșate periodic (interval 60 secunde) printr-un job DBMS_SCHEDULER. Această decizie ocolește o limitare a Oracle: opțiunea `REFRESH ON COMMIT` nu este disponibilă cross-PDB.

Aplicația-client se conectează la `VANZARI` și operează asupra view-urilor de transparență (`V_FISE_CLIENTI`, `V_LINII_DOC`, `V_ITEMS` care e local în `CATALOG` dar replicat) și a MV-urilor. Pentru operațiile de scriere, triggere `INSTEAD OF` rutează insert-urile către fragmentul corect pe baza valorii predicatului de fragmentare (de exemplu, `moneda = 'RON'` =\> `FISE_CLIENTI_RO`).

# 4 Argumentarea deciziei de fragmentare

Decizia de fragmentare urmează trei criterii: (1) maximizarea local-ității de acces pentru workload-ul dominant, (2) reducerea volumului transferat pe rețea în query-urile distribuite, (3) coerența semantică între fragmente și unitățile de business reprezentate. Aplicăm trei tehnici: fragmentare orizontală primară (pe `FISE_CLIENTI`), fragmentare orizontală derivată (pe `LINII_DOC`) și fragmentare verticală pe `MS_ITEMS`.

## 4.1 Fragmentare orizontală primară pe FISE_CLIENTI

### 4.1.1 Workload și predicate candidate

Volumul observat în datele reale arată că documentele se grupează natural pe două dimensiuni eligibile pentru fragmentare: anul calendaristic și moneda. Distribuția aproximativă în setul de 2.048 de documente este:

  ----------------------------------------------------------------------------------------------------------------
  Dimensiune                 Valori distincte                     Distribuție (aproximativă)
  -------------------------- ------------------------------------ ------------------------------------------------
  `data_doc_efectiva` (an)   2021, 2022, 2023, 2024, 2025, 2026   relativ uniformă pe ultimii 4 ani

  `moneda`                   RON, EUR, CZK, USD                   \~76% RON, \~24% non-RON (EUR + CZK + rar USD)
  ----------------------------------------------------------------------------------------------------------------

Fragmentarea pe an ar produce 6 parti, dintre care două (2021, 2026) au volum mic - pattern neuniform. Mai grav, criteriul anului nu se corelează cu nicio decizie de business (toate zonele scriu documente în toți anii).

Fragmentarea pe monedă, în schimb, se corelează cu un criteriu puternic: documentele în RON aparțin în proporție mare zonelor interne (ARDEAL, MOLDOVA, SUD), iar cele în EUR/CZK aparțin zonelor externe (SLOVACIA, CEHIA). Aceasta face fragmentarea pe monedă atât eficientă tehnic (volume echilibrate \~3:1), cât și semnificativă semantic.

### 4.1.2 Aplicarea algoritmului COM_MIN

Algoritmul COM_MIN identifică un set minim și complet de predicate pentru fragmentare, pornind de la predicatele simple candidate. Mulțimea inițială:

$$\Pr = \{ p_{1}:\text{moneda} = \text{’RON’},\ p_{2}:\text{moneda} = \text{’EUR’},\ p_{3}:\text{moneda} = \text{’CZK’},\ p_{4}:\text{moneda} = \text{’USD’}\}$$

**Pasul 1 -Test de relevanță**. Un predicat $p_{i}$ este relevant dacă există un acces la datele filtrate de $p_{i}$ care răspunde diferit de cel filtrat de $\neg p_{i}$. Pentru $p_{1}$: workload-ul de raportare per zonă filtrează documentele RON (operațiuni domestice) separat de cele non-RON (operațiuni externe). Diferența numerică este semnificativă (\~1555 vs. \~493 de documente), iar predicatul devine util pentru a localiza documentele cu zonele corespunzătoare. Identic $p_{2}$, $p_{3}$.

Predicatul $p_{4}$ (`moneda = 'USD'`) are mai puțin de 1% din volum și nu apare ca filtru frecvent în workload-ul real. Îl considerăm marginal -îl absorbim în clusterul „non-RON" împreună cu EUR și CZK.

**Pasul 2 -Test de completitudine**. Un set de predicate este complet dacă reuniunea lor acoperă întreg domeniul. Verificare empirică:

> SELECT DISTINCT moneda FROM fise_clienti;
>     -- returnează exact 4 valori: RON, EUR, CZK, USD

Predicatele $p_{1} \vee p_{2} \vee p_{3} \vee p_{4}$ acoperă întreg domeniul `moneda` ⇒ set complet.

**Pasul 3 -Minimalitate și simplificare**. Setul $\{ p_{1},p_{2},p_{3},p_{4}\}$ este minimal (fără redundanță), dar generează 4 fragmente. Aplicând criteriul de coerență geografică (RO domestic vs. extern), fuzionăm $p_{2}$, $p_{3}$, $p_{4}$ într-un singur predicat compus „non-RON". Această fuziune este o decizie de design care simplifică modelul în detrimentul granularității - argumentată prin faptul că tehnicile de optimizare ulterioare (raportarea per țară) pot folosi filtre suplimentare în interiorul fragmentului non-RON, fără să justifice fragmente fizice separate pentru EUR, CZK și USD.

Setul final de predicate compuse minimale și complete:

$$M = \{ m_{1}:\text{moneda} = \text{’RON’},\ m_{2}:\text{moneda} \neq \text{’RON’}\}$$

### 4.1.3 Fragmentele orizontale primare obținute

$$FISE\_ CLIENTI\_ RO = \sigma_{\text{moneda} = 'RON'}(FISE\_ CLIENTI)$$

$$FISE\_ CLIENTI\_ EXT = \sigma_{\text{moneda} \neq 'RON'}(FISE\_ CLIENTI)$$

Volume efective după impartite: 1.555 documente în `FISE_CLIENTI_RO`, 493 în `FISE_CLIENTI_EXT` (total 2.048). Fragmentele se stochează în nodul `VANZARI` și se accesează unitar prin view-ul `V_FISE_CLIENTI = FISE_CLIENTI_RO UNION ALL FISE_CLIENTI_EXT`.

## 4.2 Fragmentare orizontală derivată pe LINII_DOC

### 4.2.1 Legătura între relații prin cheie compusă

`LINII_DOC` este o relație membru al cărei stapan este `FISE_CLIENTI` - fiecare linie aparține unui și numai unui document, iar legătura se realizează prin cheia externă compusă $(nr\_ document,doc\_ type\_ xrp)$. Întrucât owner-ul este deja fragmentat orizontal, este natural ca member-ul să-l urmeze (fragmentare derivată), pentru a evita join-uri cross-fragment costisitoare.

Graful de fragmentare este simplu: fiecare linie are exact un header. Această condiție este necesară pentru ca împărtirea fragmentelor derivate să fie automată - niciun tuplu de linie nu poate aparține simultan la două fragmente diferite.

### 4.2.2 Fragmentele orizontale derivate obținute

Aplicăm operatorul de semijoin față de cele două fragmente ale owner-ului:

$$LINII\_ DOC\_ RO = LINII\_ DOC \ltimes FISE\_ CLIENTI\_ RO$$

$$LINII\_ DOC\_ EXT = LINII\_ DOC \ltimes FISE\_ CLIENTI\_ EXT$$

Semijoin-ul aduce criteriul de selecție de la owner la member fără a duplica atribute. Volumele efective: 3.806 linii în `LINII_DOC_RO`, 1.712 în `LINII_DOC_EXT` (total 5.518 -din 5.598 inițiale au fost eliminate 80 linii orfane, adică linii al căror `item_code` nu mai avea corespondent în `MS_ITEMS` în setul de date selectat; eliminarea s-a făcut la reglementarea cheii externe către `MV_ITEMS_CORE`).

Fragmentele se stochează tot în nodul `VANZARI` și se accesează unitar prin view-ul `V_LINII_DOC = LINII_DOC_RO UNION ALL LINII_DOC_EXT`. Cheia externă către owner se păstrează intra-fragment (`LINII_DOC_RO` referențiază `FISE_CLIENTI_RO`, `LINII_DOC_EXT` referențiază `FISE_CLIENTI_EXT`), ceea ce permite Oracle să optimizeze join-urile prin *partition-wise execution* natural.

## 4.3 Fragmentare verticală pe ITEMS (algoritmul BEA)

### 4.3.1 Workload și matricea de utilizare a atributelor

Tabela `MS_ITEMS` are 15 atribute, dintre care `id` (cheia primară) va fi replicat în ambele fragmente pentru a permite reconstrucția prin join.

Pentru aplicarea algoritmului avem nevoie de un workload reprezentativ. Cele 5 tipuri de query-uri de mai jos reprezintă cazurile dominante:

  ---------------------------------------------------------------------------------------------------------------------------
  Cod                     Aplicație                                                                   Frecvență (acc/lună)
  ----------------------- --------------------------------------------------------------------------- -----------------------
  $$q_{1}$$               Catalog browse -agenții consultă produsele cu identificare și clasificare   25

  $$q_{2}$$               Insert linie factură -necesită `item_code` și `item_name` pentru validare   85

  $$q_{3}$$               Raport top vânzări (lunar) -agregare pe categorie                           1

  $$q_{4}$$               Editare fișă produs (admin) -descriere, TVA, barcode, greutate, UM          25

  $$q_{5}$$               Update cost & furnizor (per produs) -cost și cod furnizor                   30
  ---------------------------------------------------------------------------------------------------------------------------

Frecvențele sunt derivate empiric din volumul real (5.598 linii într-o perioadă de 66 de luni dă o medie de \~85 inserări/lună) și completate cu estimări pentru workload-ul de gestiune.

Matricea de utilizare $VA$ (1 dacă atributul este accesat de query, 0 altfel). Notăm atributele non-cheie cu indici $A_{1}$..$A_{14}$ în ordinea: `item_code`, `item_name`, `item_description`, `brand_id`, `season_id`, `item_type_id`, `category_id`, `active`, `vat`, `last_cost_price`, `main_barcode`, `supplier_code`, `weight`, `um`.

  ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
              $$A_{1}$$   $$A_{2}$$   $$A_{3}$$   $$A_{4}$$   $$A_{5}$$   $$A_{6}$$   $$A_{7}$$   $$A_{8}$$   $$A_{9}$$   $$A_{10}$$   $$A_{11}$$   $$A_{12}$$   $$A_{13}$$   $$A_{14}$$
  ----------- ----------- ----------- ----------- ----------- ----------- ----------- ----------- ----------- ----------- ------------ ------------ ------------ ------------ ------------
  $$q_{1}$$   1           1           0           1           1           1           1           1           0           0            0            0            0            0

  $$q_{2}$$   1           1           0           0           0           0           0           0           0           0            0            0            0            0

  $$q_{3}$$   1           1           0           0           0           0           1           0           0           0            0            0            0            0

  $$q_{4}$$   0           1           1           0           0           0           0           0           1           0            1            0            1            1

  $$q_{5}$$   0           0           0           0           0           0           0           0           0           1            0            1            0            0
  ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

### 4.3.2 Aplicarea algoritmului BEA și algoritmul PART

Afinitatea între două atribute $A_{i}$ și $A_{j}$ se calculează prin formula:

$$aff(A_{i},A_{j}) = \sum_{q \mid use(q,A_{i}) = use(q,A_{j}) = 1}^{}{acc}(q)$$

Două perechi exemplificative:

**Perechea (**$A_{1}$**,** $A_{2}$**) = (item_code, item_name)**: ambele atribute sunt accesate de $q_{1}$, $q_{2}$ și $q_{3}$, deci:

$$aff(A_{1},A_{2}) = acc(q_{1}) + acc(q_{2}) + acc(q_{3}) = 25 + 85 + 1 = 111$$

Aceasta este afinitatea maximă din toată matricea -codul și numele sunt aproape întotdeauna citite împreună.

**Perechea (**$A_{1}$**,** $A_{13}$**) = (item_code, weight)**: niciun query nu le accesează simultan, deci:

$$aff(A_{1},A_{13}) = 0$$

Afinitate zero - `item_code` ține de identificare/clasificare, `weight` ține de atribute fizice administrative.

După calculul tuturor celor 91 de perechi posibile și permutarea coloanelor matricei AA (criteriu: maximizarea contribuției globale), matricea CA permutată evidențiază clar două clustere de atribute cu afinitate intra-grup ridicată și afinitate inter-grup scăzută:

- **Cluster CORE**: $\{ A_{1},A_{2},A_{4},A_{5},A_{6},A_{7},A_{8}\}$ - `item_code`, `item_name`, `brand_id`, `season_id`, `item_type_id`, `category_id`, `active`
- **Cluster EXTRA**: $\{ A_{3},A_{9},A_{10},A_{11},A_{12},A_{13},A_{14}\}$ - `item_description`, `vat`, `last_cost_price`, `main_barcode`, `supplier_code`, `weight`, `um`

Pentru a alege punctul concret de bipartiție, aplicăm algoritmul PART, care maximizează funcția obiectiv:

$$z = CTQ \cdot CBQ - {COQ}^{2}$$

unde $CTQ$ = suma frecvențelor query-urilor care accesează doar atribute din clusterul CORE, $CBQ$ = suma pentru clusterul EXTRA, iar $COQ$ = suma pentru query-urile care accesează atribute din ambele clustere. Pentru bipartiția propusă:

- $TQ = \{ q_{1},q_{2},q_{3}\}$ -accesează doar atribute CORE =\> $CTQ = 25 + 85 + 1 = 111$
- $BQ = \{ q_{5}\}$ -accesează doar atribute EXTRA =\> $CBQ = 30$
- $OQ = \{ q_{4}\}$ -accesează atribute din ambele clustere =\> $COQ = 25$
- $z = 111 \times 30 - 25^{2} = 3.330 - 625 = \mathbf{2.705}$ -maxim global.

### 4.3.3 Fragmentele verticale obținute

$$ITEMS\_ CORE = \pi_{id,A_{1},A_{2},A_{4},A_{5},A_{6},A_{7},A_{8}}(MS\_ ITEMS)$$

$$ITEMS\_ EXTRA = \pi_{id,A_{3},A_{9},A_{10},A_{11},A_{12},A_{13},A_{14}}(MS\_ ITEMS)$$

Cheia primară `id` este replicată în ambele fragmente pentru a permite reconstrucția prin join. Volum: 3.192 de rânduri în fiecare fragment (egale, deoarece fragmentarea verticală partiționează atribute, nu tupluri).

Fragmentele se stochează în nodul `CATALOG` și se accesează unitar prin view-ul:

> CREATE OR REPLACE VIEW V_ITEMS AS
>     SELECT c.id, c.item_code, c.item_name, e.item_description,
>            c.brand_id, c.season_id, c.item_type_id, c.category_id,
>            e.vat, e.last_cost_price, e.main_barcode, e.supplier_code,
>            e.weight, e.um, c.active
>     FROM   ITEMS_CORE c
>            JOIN ITEMS_EXTRA e ON e.id = c.id;

Pentru operațiile DML peste view, triggere `INSTEAD OF` rutează inserările/actualizările/ștergerile către cele două fragmente.

# 5. Verificarea corectitudinii fragmentărilor

Pentru ca o fragmentare să fie corectă, trebuie să îndeplinească trei condiții cumulative: completitudine, reconstrucție (lossless join) și disjuncție. Verificăm cele trei condiții pentru fiecare dintre cele trei fragmentări aplicate.

  -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  Fragmentare                                       Completitudine                                                                                                                                                             Reconstrucție                                                                                                                             Disjuncție
  ------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- ----------------------------------------------------------------------------------------------------------------------------------------- --------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  Orizontală primară `FISE_CLIENTI` (pe `moneda`)   $m_{1} \vee m_{2} \equiv \text{moneda is not null}$ -verificată empiric: toate cele 2.048 documente au monedă populată                                                     $FISE\_ CLIENTI = FISE\_ CLIENTI\_ RO \cup FISE\_ CLIENTI\_ EXT$ (UNION ALL) -1.555 + 493 = 2.048, identic cu populația originală         $m_{1} \land m_{2} \equiv \text{FALSE}$ -un tuplu cu `moneda = 'RON'` nu poate satisface `moneda <> 'RON'`

  Orizontală derivată `LINII_DOC` (semijoin)        Cheia externă (`nr_document`, `doc_type_xrp`) este obligatorie (NOT NULL + FK enforcement) -fiecare linie are header, deci aparține unui fragment                          $LINII\_ DOC = LINII\_ DOC\_ RO \cup LINII\_ DOC\_ EXT$ -3.806 + 1.712 = 5.518 (după eliminarea celor 80 orfani fără `item_code` valid)   Cheia primară `id` a liniei este unică global, iar fiecare linie e legată de un singur header (cardinalitate 1) -deci aparține unui singur fragment derivat

  Verticală `MS_ITEMS` (BEA =\> CORE/EXTRA)         Atributele $A_{1}$..$A_{14}$ acoperite de reuniune: `ITEMS_CORE` are 7 + `id`, `ITEMS_EXTRA` are 7 + `id` = 14 atribute non-cheie + cheia replicată. Niciun atribut omis   $MS\_ ITEMS = ITEMS\_ CORE \bowtie_{id}ITEMS\_ EXTRA$ -join pe PK garantează reconstrucție lossless (FN3 + PK obligatoriu)                Atributele disjuncte între cele două fragmente, cu excepția cheii primare `id`, care e replicată intenționat pentru join. Disjuncția pe atribute non-cheie este completă
  -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

Verificările au fost confirmate empiric în timpul implementării prin teste de tip:

> -- Reconstrucție fragmentare orizontală
>     SELECT COUNT(*) FROM v_fise_clienti;        -- 2.048 (corect)
>     SELECT COUNT(*) FROM fise_clienti_ro;       -- 1.555
>     SELECT COUNT(*) FROM fise_clienti_ext;      -- 493
>
>     -- Disjuncția fragmentării orizontale
>     SELECT COUNT(*) FROM fise_clienti_ro
>     WHERE moneda <> 'RON';                       -- 0 (CHECK constraint împiedică)
>
>     -- Reconstrucție fragmentare verticală
>     SELECT COUNT(*) FROM v_items;                -- 3.192 (corect)
>     SELECT COUNT(*) FROM items_core c
>     WHERE NOT EXISTS (SELECT 1 FROM items_extra e WHERE e.id = c.id);  -- 0 (FK obligatoriu)

Constrângerile CHECK pe predicatele de fragmentare (`ck_fise_ro_mon: moneda = 'RON'`, `ck_fise_ext_mon: moneda <> 'RON'`) garantează la nivel de bază de date că orice insert sau update respectă disjuncția -un document nu poate „migra accidental" în fragmentul greșit.

# 6. Argumentarea deciziei de replicare

Decizia de a replica o relație sau de a o stoca pe o singură stație urmează trei criterii principale:

1.  **Volumul tabelei**. Tabele cu sub \~10.000 de rânduri pot fi replicate cu cost de stocare neglijabil. Pentru tabele mari (fact tables cu sute de mii sau milioane de rânduri), replicarea devine prohibitivă în spațiu și în timp de sincronizare.
2.  **Raportul citire/scriere**. Tabele cu citire frecventă și scriere rară (tipice pentru lookup-uri și date master) beneficiază maxim de replicare -cititorii locali nu mai depind de comunicarea cu nodul-master. Tabele cu scriere frecventă (fact tables) sunt slabe candidate, deoarece sincronizarea ar deveni costisitoare.
3.  **Locația join-urilor**. Dacă o tabelă este join-uită frecvent cu fact tables într-un nod specific, replicarea ei în acel nod elimină hop-uri remote din planurile de execuție. Atunci când join-urile sunt mai rare sau ad-hoc, accesul prin database link cu remote scan este suficient.

Aplicarea acestor criterii produce deciziile concrete:

  -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
                     Tabel                        Master în        Replicat în                                                                  Justificare
  ------------------------------------------- ----------------- ----------------- ---------------------------------------------------------------------------------------------------------------------------------------
                    `zone`                       DISTRIBUTIE         VANZARI                   Volum mic (5 rânduri), citită în orice raport de vânzări pe zonă. Replicarea elimină 1 hop la fiecare query.

                   `clienti`                     DISTRIBUTIE         VANZARI                  Volum mic (10 rânduri), FK cross-PDB din `FISE_CLIENTI` -replicarea permite enforcement local al constrângerii.

                 `items_core`                      CATALOG           VANZARI                                  3.192 rânduri, FK cross-PDB din `LINII_DOC` -necesar pentru enforcement local.

                   `brands`                        CATALOG           VANZARI                                          131 rânduri, join frecvent în rapoarte (top branduri vândute).

               `items_category`                    CATALOG           VANZARI                                    15 rânduri, join obligatoriu în cererea complexă (top agenți pe categorie).

                 `items_type`                      CATALOG           VANZARI                                                     3 rânduri, lookup în rapoarte sezoniere.

                `items_seasons`                    CATALOG           VANZARI                                                     17 rânduri, lookup în rapoarte sezoniere.

                 `items_extra`                     CATALOG          nicăieri                            Atribute administrative (cost, furnizor), acces strict local pentru rolul de admin produse.

                   `agenti`                      DISTRIBUTIE        nicăieri       Acces ad-hoc din cererea complexă; replicarea ar avea cost de sincronizare fără beneficiu măsurabil în absența join-urilor frecvente.

     `zone_agenti`, `zone_intervale_plata`       DISTRIBUTIE        nicăieri                    Asocieri temporale M:N -accesate doar prin DB link în cererea complexă, cu predicate temporale restrictive.

   `intervale_plata`, `intervale_plata_zile`     DISTRIBUTIE        nicăieri                                                 Acces ad-hoc, lookup pentru calculul scadențelor.

        `fise_clienti_*`, `linii_doc_*`            VANZARI          nicăieri              Fact tables fragmentate orizontal; volum mare, scriere intensă. Replicarea ar contraveni întregului design distribuit.
  -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

Replicarea se implementează prin materialized views cu refresh FAST în mod ON DEMAND. Logurile de materialized view (`CREATE MATERIALIZED VIEW LOG ON tabel ...`) instalate pe tabela master capturează modificările incremental, iar refresh-ul propagă doar delta - un mecanism eficient pentru volume mici și moderate. Sincronizarea se face printr-un job DBMS_SCHEDULER cu interval de 60 de secunde, ales ca trade-off între prospețime și cost de overhead. Lag-ul maxim acceptat (60 secunde) este compatibil cu rapoartele și operațiile interactive obișnuite; pentru cazuri care necesită prospețime maximă, refresh-ul poate fi forțat manual prin `DBMS_MVIEW.REFRESH(...)`.

# 7. Schemele conceptuale locale

După fragmentare și distribuție, schema conceptuală globală se descompune în trei scheme locale, una per PDB. Schemele locale prezintă tabelele fizice (master + fragmente + materialized views), cheile primare și externe, plus view-urile de transparență.

## 7.1. Schema PDB DISTRIBUTIE

Nodul `DISTRIBUTIE` păstrează 8 tabele master fără fragmentare - toate au volum mic și sunt accesate fie local pentru CRM, fie remote prin DB link pentru join-uri în cererea complexă.

![](build/proiect/media-partea1/media/image7.svg){width="6.531944444444444in" height="2.776388888888889in"}

Schema conceptuală locală -PDB DISTRIBUTIE

Cheile primare sunt simple (un singur `id` per tabelă), cu excepția `INTERVALE_PLATA_ZILE` care are cheie compusă `(id_interval, per_zile)`. Cheile externe locale (intra-PDB) sunt 8: `clienti ``=>`` zone`, `clienti_contacte ``=>`` clienti`, `zone_agenti ``=>`` zone`, `zone_agenti ``=>`` agenti`, `zone_intervale_plata ``=>`` zone`, `zone_intervale_plata ``=>`` intervale_plata`, `intervale_plata_zile ``=>`` intervale_plata`, plus auto-referință `zone ``=>`` zone` (parent).

## 7.2 Schema PDB CATALOG

Nodul `CATALOG` găzduiește catalogul de produse, cu fragmentarea verticală aplicată pe `MS_ITEMS`. Cele două fragmente fizice (`ITEMS_CORE` și `ITEMS_EXTRA`) sunt expuse unitar prin view-ul `V_ITEMS`, care realizează transparența verticală - aplicația-client vede o singură tabelă logică.

![](build/proiect/media-partea1/media/image9.svg){width="6.531944444444444in" height="4.773611111111111in"}

Schema conceptuală locală - PDB CATALOG

`ITEMS_EXTRA` are PK = FK către `ITEMS_CORE` (relație 1:1, cu ON DELETE CASCADE), ceea ce garantează că orice produs din CORE are exact o intrare în EXTRA. Există 4 chei externe locale (de la `ITEMS_CORE` către cele patru lookup-uri) plus FK-ul 1:1 între cele două fragmente.

Triggere INSTEAD OF pe `V_ITEMS` rutează inserările, actualizările și ștergerile către ambele fragmente - aplicația nu trebuie să cunoască existența split-ului vertical.

## 7.3 Schema PDB VANZARI

Nodul `VANZARI` este cel mai complex din punct de vedere structural: găzduiește 4 fragmente fizice orizontale (cele 2 fragmente de fișe × cele 2 fragmente de linii), 2 view-uri de transparență (`V_FISE_CLIENTI`, `V_LINII_DOC`) și 7 materialized views replicate din celelalte două noduri.

![](build/proiect/media-partea1/media/image11.svg){width="6.531944444444444in" height="5.298611111111111in"}

Schema conceptuală locală -PDB VANZARI

Cheile externe locale intra-PDB sunt 2: `LINII_DOC_RO ``=>`` FISE_CLIENTI_RO` și `LINII_DOC_EXT ``=>`` FISE_CLIENTI_EXT` (pe cheia compusă `(nr_document, doc_type_xrp)`). Cheile externe către tabelele replicate (cross-PDB la nivel logic, dar locale la nivel de Oracle deoarece referențiază MV-uri replicate) sunt 4:

- `FISE_CLIENTI_RO.cod_client ``=>`` MV_CLIENTI.cod_client`
- `FISE_CLIENTI_EXT.cod_client ``=>`` MV_CLIENTI.cod_client`
- `LINII_DOC_RO.item_code ``=>`` MV_ITEMS_CORE.item_code`
- `LINII_DOC_EXT.item_code ``=>`` MV_ITEMS_CORE.item_code`

Triggere INSTEAD OF pe `V_FISE_CLIENTI` și `V_LINII_DOC` rutează DML-ul către fragmentele corecte pe baza predicatului de fragmentare (`moneda` pentru fișe). Aplicația-client lucrează exclusiv cu view-urile -fragmentarea orizontală este complet ascunsă.

# 8. Constrângeri de integritate

Constrângerile de integritate acoperă patru categorii: unicitate, chei primare, chei externe și validări semantice. Pentru fiecare, distingem între nivelul local și nivelul global.

## 8.1. Constrângeri de unicitate

### 8.1.1 Unicitate locală

Fiecare PDB are propriile constrângeri UK pentru atributele care identifică o entitate dincolo de cheia surogat numerică:

  ------------------------------------------------------------------
  PDB           Tabel                UK
  ------------- -------------------- -------------------------------
  DISTRIBUTIE   `zone`               `cod_zona`

  DISTRIBUTIE   `agenti`             `cod_agent`

  DISTRIBUTIE   `clienti`            `cod_client`

  DISTRIBUTIE   `intervale_plata`    `den_interval`

  CATALOG       `brands`             `code`

  CATALOG       `items_category`     `code`

  CATALOG       `items_type`         `code`

  CATALOG       `items_seasons`      `code`

  CATALOG       `items_core`         `item_code`

  VANZARI       `fise_clienti_ro`    `(nr_document, doc_type_xrp)`

  VANZARI       `fise_clienti_ext`   `(nr_document, doc_type_xrp)`
  ------------------------------------------------------------------

### 8.1.2 Unicitate globală pe fragmente orizontale

Pentru o relație fragmentată orizontal, cheia logică trebuie să rămână unică la nivel global, nu doar în interiorul fragmentului. Pentru `FISE_CLIENTI`, cheia logică este `(nr_document, doc_type_xrp)` și trebuie să fie unică între `FISE_CLIENTI_RO` și `FISE_CLIENTI_EXT`.

Această unicitate globală este asigurată implicit prin construcție: predicatele de fragmentare sunt disjuncte (`moneda = 'RON'` ⊥ `moneda <> 'RON'`), deci un tuplu cu o anumită cheie logică nu poate exista simultan în ambele fragmente. Impreuna cu UK locală în fiecare fragment, cheia logică globală este unică prin design.

Aceeași logică se aplică pentru `LINII_DOC` - cheia primară `id` este unică în fiecare fragment (`LINII_DOC_RO`, `LINII_DOC_EXT`), iar o linie aparține unui singur fragment (urmează owner-ul prin semijoin).

### 8.1.3 Unicitate globală pe fragmente verticale

Pentru fragmentarea verticală a `MS_ITEMS`, problema de unicitate are altă natură: atributul de identificare a produsului (`item_code`) trebuie să rămână unic global. Acest atribut este însă plasat doar în fragmentul `ITEMS_CORE` (nu este replicat în `ITEMS_EXTRA`), deci unicitatea sa locală în CORE este și globală.

Cheia primară `id` este replicată în ambele fragmente pentru a permite reconstrucția. Pentru a asigura că un anumit `id` nu există fără pereche în ambele fragmente, am definit FK-ul `ITEMS_EXTRA.id ``=>`` ITEMS_CORE.id ON DELETE CASCADE`, care garantează corespondența 1:1 între fragmente.

## 8.2 Chei primare

### 8.2.1 La nivel local

Toate tabelele au cheie primară definită explicit prin constrângere `PRIMARY KEY`. În toate cazurile cu o singură excepție` ``INTERVALE_PLATA_ZILE` numeric (`id NUMBER(19)`), care folosește PK compus `(id_interval, per_zile)` -atributele cheii sunt semnificative din punct de vedere business (un interval poate avea mai multe perioade de zile distincte, fiecare cu propria denumire).

Pentru `CLIENTI_CONTACTE`, PK-ul `cod_client` este simultan și FK către `CLIENTI.cod_client` -relație 1:1 strictă (un client are un singur contact).

### 8.2.2 La nivel global pe fragmente orizontale

Pentru `FISE_CLIENTI` reconstituit prin `V_FISE_CLIENTI`, cheia primară globală este `id` -unic în fiecare fragment și unic global prin convenția de generare a ID-urilor (secvențe care nu se suprapun). Acest invariant este menținut aplicativ; o verificare suplimentară poate fi adăugată ca trigger global care interzice insert-uri cu `id` deja prezent în fragmentul opus (acceptabil pentru volumul implicat).

Pentru `LINII_DOC` reconstituit prin `V_LINII_DOC`, cheia primară globală `id` este unică prin construcție (semijoin-ul nu duplică tupluri).

Pentru `MS_ITEMS` reconstituit prin `V_ITEMS`, cheia primară globală este `id` -unică în `ITEMS_CORE` (UK local), și replicată în `ITEMS_EXTRA` prin FK.

## 8.3 Chei externe

### 8.3.1 La nivel local (intra-PDB)

  ----------------------------------------------------------------------------------------------------------------------
  PDB                     FK                                            Referință
  ----------------------- --------------------------------------------- ------------------------------------------------
  DISTRIBUTIE             `clienti.id_zona`                             `zone.id`

  DISTRIBUTIE             `clienti_contacte.cod_client`                 `clienti.cod_client`

  DISTRIBUTIE             `zone_agenti.id_zona`                         `zone.id`

  DISTRIBUTIE             `zone_agenti.id_agent`                        `agenti.id`

  DISTRIBUTIE             `zone_intervale_plata.id_zona`                `zone.id`

  DISTRIBUTIE             `zone_intervale_plata.id_interval`            `intervale_plata.id`

  DISTRIBUTIE             `intervale_plata_zile.id_interval`            `intervale_plata.id`

  DISTRIBUTIE             `zone.parent_zona_id` (self-FK)               `zone.id`

  CATALOG                 `items_core.brand_id`                         `brands.id`

  CATALOG                 `items_core.season_id`                        `items_seasons.id`

  CATALOG                 `items_core.item_type_id`                     `items_type.id`

  CATALOG                 `items_core.category_id`                      `items_category.id`

  CATALOG                 `items_extra.id` (PK = FK)                    `items_core.id` ON DELETE CASCADE

  VANZARI                 `linii_doc_ro.(nr_document, doc_type_xrp)`    `fise_clienti_ro.(nr_document, doc_type_xrp)`

  VANZARI                 `linii_doc_ext.(nr_document, doc_type_xrp)`   `fise_clienti_ext.(nr_document, doc_type_xrp)`
  ----------------------------------------------------------------------------------------------------------------------

### 8.3.2 Pentru relații stocate în baze de date diferite

Cheile externe cross-PDB nu pot fi declarate direct între tabele din PDB-uri diferite (limitare Oracle). Soluția adoptată: replicăm tabelele referențiate ca materialized views în PDB-ul referențiator și definim FK-urile către aceste MV-uri. Sincronizarea MV-urilor (job @ 60s) garantează că enforcement-ul FK reflectă starea master cu un lag controlat.

Cele 4 FK-uri cross-PDB implementate:

  ----------------------------------------------------------------------------------------------
  FK                              Referință (master)                 Reference locală (MV)
  ------------------------------- ---------------------------------- ---------------------------
  `fise_clienti_ro.cod_client`    `clienti@DISTRIBUTIE.cod_client`   `mv_clienti.cod_client`

  `fise_clienti_ext.cod_client`   `clienti@DISTRIBUTIE.cod_client`   `mv_clienti.cod_client`

  `linii_doc_ro.item_code`        `items_core@CATALOG.item_code`     `mv_items_core.item_code`

  `linii_doc_ext.item_code`       `items_core@CATALOG.item_code`     `mv_items_core.item_code`
  ----------------------------------------------------------------------------------------------

Trade-off-ul acceptat: până la refresh-ul MV-ului (max 60 secunde după un INSERT în master), un INSERT în VANZARI care referențiază un cod nou ar putea eșua tranzitoriu. Pentru cazurile critice, se forțează refresh manual înainte de operațiunea dependentă.

## 8.4 Constrângeri de validare

### 8.4.1 La nivel local

CHECK-uri pe domenii și pe combinații logice de atribute:

  --------------------------------------------------------------------------------------------------------------------------------------
  Tabel                    Constrângere                                                          Semnificație
  ------------------------ --------------------------------------------------------------------- ---------------------------------------
  `fise_clienti_*`         `tip_doc IN ('F','I')`                                                Documentul este factură sau încasare

  `fise_clienti_*`         `doc_type_xrp IN ('INV','PMT','CRM','PPM','REF','RPM','DRM','VRF')`   Tip XRP în mulțimea de coduri permise

  `fise_clienti_*`         `semn IN (-1, 1)`                                                     Direcția contabilă

  `fise_clienti_ro`        `moneda = 'RON'`                                                      Predicat de fragmentare

  `fise_clienti_ext`       `moneda <> 'RON'`                                                     Predicat de fragmentare

  `items_seasons`          `active IN (0, 1)`                                                    Boolean flag

  `clienti`                `end_date IS NULL OR end_date > start_date`                           Interval temporal valid

  `zone_agenti`            `end_date IS NULL OR end_date > start_date`                           Interval temporal valid

  `zone_intervale_plata`   `end_date IS NULL OR end_date > start_date`                           Interval temporal valid
  --------------------------------------------------------------------------------------------------------------------------------------

CHECK-urile pe predicatele de fragmentare (`ck_fise_ro_mon`, `ck_fise_ext_mon`) au un rol dublu: definesc semantica fragmentului și împiedică inserturi „pe fragmentul greșit", indiferent de calea de acces (direct sau prin view-ul de transparență).

### 8.4.2 Pentru relații stocate în baze de date diferite

Validările cross-PDB se implementează prin triggere care fac join-uri remote sau prin agregate calculate post-INSERT. Cazul concret implementat: **coerența între suma documentului și suma liniilor lui**.

Pentru fiecare document din `FISE_CLIENTI_*`, valoarea totală (`amount_doc`) trebuie să fie aproximativ egală cu suma valorilor liniilor (`SUM(xrp_linie_valoare_fara_tva + xrp_linie_tva)` peste `LINII_DOC_*` cu același `(nr_document, doc_type_xrp)`). Toleranța acceptată este 0.01 RON (eroare de rotunjire la împărțirea TVA-ului).

Implementarea este un trigger `AFTER INSERT OR UPDATE OR DELETE ON linii_doc_*` care recalculează agregatul după fiecare modificare și ridică `RAISE_APPLICATION_ERROR` dacă diferența depășește toleranța:

> CREATE OR REPLACE TRIGGER trg_coerenta_sum_ro
>     AFTER INSERT OR UPDATE OR DELETE ON linii_doc_ro
>     DECLARE
>       CURSOR c IS
>         SELECT f.nr_document, f.doc_type_xrp,
>                f.amount_doc AS doc_total,
>                SUM(l.xrp_linie_valoare_fara_tva + l.xrp_linie_tva) AS sum_linii
>         FROM fise_clienti_ro f
>              JOIN linii_doc_ro l ON (l.nr_document, l.doc_type_xrp) = (f.nr_document, f.doc_type_xrp)
>         GROUP BY f.nr_document, f.doc_type_xrp, f.amount_doc
>         HAVING ABS(f.amount_doc - SUM(l.xrp_linie_valoare_fara_tva + l.xrp_linie_tva)) > 0.01;
>     BEGIN
>       FOR r IN c LOOP
>         RAISE_APPLICATION_ERROR(-20001, 'Incoerenta suma pe ' || r.nr_document || '/' || r.doc_type_xrp);
>       END LOOP;
>     END;

Un trigger similar (`trg_coerenta_sum_ext`) acoperă fragmentul EXT.

# 9 Cererea SQL complexă și tehnici de optimizare

Pentru a demonstra valoarea modelului distribuit, am formulat o cerere SQL complexă care implică toate cele 3 PDB-uri și care va fi optimizată în modulul de implementare backend.

**Limbaj natural**: *Care sunt cei 10 agenți cu cea mai mare valoare totală vândută în anul 2024, defalcată pe zonă comercială și categorie de produs, luând în calcul doar facturile efective (*`tip_doc = 'F'`*)?*

Cererea folosește simultan: agenții și asocierea zone--agenți (din `DISTRIBUTIE`, accesate prin DB link), documentele și liniile lor (din `VANZARI`, prin view-urile de transparență), zonele și categoriile de produs (replicate ca MV-uri în `VANZARI`). Implică un join de 8 relații și două agregări (suma valorilor pe combinație agent--zonă--categorie, urmată de un Top-N).

**Formularea SQL**:

> SELECT a.nume_agent, z.den_zona, c.name AS categorie,
>            SUM(ld.xrp_linie_valoare_fara_tva) AS total_2024
>     FROM   v_fise_clienti f
>            JOIN v_linii_doc ld
>                 ON ld.nr_document = f.nr_document
>                AND ld.doc_type_xrp = f.doc_type_xrp
>            JOIN mv_clienti cli           ON cli.cod_client = f.cod_client
>            JOIN mv_zone z                ON z.id = cli.id_zona
>            JOIN zone_agenti@lnk_distributie za
>                 ON za.id_zona = cli.id_zona
>                AND f.data_doc_efectiva BETWEEN za.start_date
>                                            AND NVL(za.end_date, DATE '9999-12-31')
>            JOIN agenti@lnk_distributie a ON a.id = za.id_agent
>            JOIN mv_items_core ic         ON ic.item_code = ld.item_code
>            JOIN mv_items_category c      ON c.id = ic.category_id
>     WHERE  f.tip_doc = 'F'
>       AND  f.data_doc_efectiva >= DATE '2024-01-01'
>       AND  f.data_doc_efectiva <  DATE '2025-01-01'
>     GROUP BY a.nume_agent, z.den_zona, c.name
>     ORDER BY total_2024 DESC
>     FETCH FIRST 10 ROWS ONLY;

**Tehnici de optimizare candidate**:

  ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  Tehnică                                             Avantaje                                                                                                                                                               Dezavantaje
  --------------------------------------------------- ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------------
  **Optimizator bazat pe regulă (RBO)**               Predictibil, nu necesită statistici. Aplicabil când statisticile lipsesc sau sunt depășite.                                                                            Ignoră selectivitățile reale; alege deseori ordine de join suboptimală în query-uri distribuite.

  **Optimizator bazat pe cost (CBO)**                 Folosește statistici (cardinalități, distribuții) pentru a alege ordinea de join și algoritmii (nested loops vs. hash) optim.                                          Necesită `DBMS_STATS` proaspăt. Pe MV-uri replicate, estimările pot fi imprecise dacă statisticile nu sunt regenerate după refresh.

  **Partition pruning pe predicate de fragmentare**   Reduce I/O drastic -predicate care coincid cu predicatul de fragmentare scanează doar fragmentul relevant (de exemplu, `moneda = 'RON'` =\> doar `FISE_CLIENTI_RO`).   Se aplică automat doar dacă predicatul este detectabil de optimizer; necesită view-uri scrise cu UNION ALL, nu UNION distinct.

  **Indexare selectivă**                              Indecși pe coloanele cele mai filtrate (`data_doc_efectiva`, `cod_client`, `tip_doc`) accelerează scan-urile range și join-urile.                                      Cost de menținere la INSERT/UPDATE; trebuie balansat cu workload-ul real.

  **Hint** `DRIVING_SITE`                             Forțează asamblarea rezultatului într-un nod specific, util când optimizer-ul nu alege site-ul cu cel mai mic volum de date transferat.                                Decizie manuală; riscă să devină greșit la schimbarea volumelor.

  **Materialized View cu query rewrite**              Pre-calculează agregările frecvente (de exemplu, total per agent--zonă--lună); optimizer-ul poate rescrie query-ul să citească din MV.                                 Necesită refresh periodic; potențial date stale.

  **Semijoin pentru relații remote mici**             Reduce volumul transferat pe rețea -în loc să transferăm întreaga relație remote, transferăm doar cheile filtrului.                                                    Adaugă o etapă suplimentară de comunicare; benefică doar când relația remote este mare și filtrul reduce semnificativ volumul.
  ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

Compararea concretă a planurilor de execuție (RBO vs. CBO vs. DRIVING_SITE), cu costuri și timpii observați, este detaliată în raportul modulului de implementare backend.

# 10 Bibliografie și notă de transparență

## 10.1 Surse tehnice și implementare proprie

Acest raport descrie un sistem implementat de autor în perioada 2026-04 ⬄ 2026-05, sub formă de 18 commit-uri în repository-ul local de proiect. Implementarea backend (DDL Oracle, scripturi de încărcare, view-uri de transparență, MV-uri, triggere, indecși, query-uri optimizate) este conținută în directorul `modbd/oracle/` și a fost validată end-to-end prin script-ul `test_validation.sql`.

Documentele anexe la prezentul raport (parte integrantă a livrabilului proiectului):

- Fișierul-sursă SQL/PL-SQL: SOP`_``Sursa.txt`
- Print-screen-urile rulării în Oracle: incluse în fișierul proiect integrat
- Raportul modulului de implementare backend SOP`_``Proiect.docx`

## 10.2 Notă de transparență privind utilizarea AI

Acest raport a fost redactat de echipa, pe baza implementării realizate, a codului scris și a erorilor depanate în timpul celor 17 task-uri tehnice ale modulului 2. Asistența unui sistem AI a fost folosită în două situații, ambele declarate explicit:

1.  **Anonimizarea datelor sursă** -înlocuirea codurilor reale de client (numere cu 9 cifre, identificabile public) cu identificatori fictivi CLI000001..CLI000010, și generarea numelor fictive pentru clienți și agenți. Mapping-ul este determinist și aplicat consistent în toate cele 15 fișiere CSV. Această operațiune a fost necesară pentru protecția datelor cu caracter personal, conform politicilor de confidențialitate ale sursei reale a datelor.
2.  **Verificare gramaticală și structurare** -pentru corectarea acordurilor, punctuație, structura unor paragrafe și consecvența terminologică. Conținutul tehnic (deciziile arhitecturale, algoritmii, formulele, codul SQL, analizele) este produs de autor pe baza implementării proprii.

Sistemul AI nu a generat: deciziile de fragmentare, algoritmii BEA/COM_MIN aplicați, codul SQL, structura matricilor de utilizare, alegerile arhitecturale (3 PDB-uri vs. alte alternative), schema relațională, sau analizele de optimizare.


\newpage

# PARTEA II --- IMPLEMENTAREA BAZEI DE DATE (MODULUL 2)

Această parte demonstrează implementarea efectivă în Oracle 21c a bazei de date distribuite. Pentru fiecare cerință din baremul Modulului 2, prezentăm codul SQL/PL-SQL folosit (inline, ca text) urmat de capturi de ecran care confirmă rularea cu succes în Oracle.

## 1. Crearea bazelor de date și a utilizatorilor (0.5p, obligatoriu)

Sistemul nostru folosește 3 PDB-uri (Pluggable Databases) într-un singur CDB Oracle 21c XE: `DISTRIBUTIE`, `CATALOG` și `VANZARI`. Fiecare PDB are propriul utilizator aplicativ și propriul rol cu grant-urile necesare.

### 1.1 Crearea PDB-urilor

Scriptul `01_create_pdbs.sql` rulează ca `SYS` cu rol `SYSDBA` în CDB$ROOT și creează cele trei PDB-uri:

```sql
ALTER SESSION SET CONTAINER = CDB$ROOT;

-- Eliminam PDB-ul default XEPDB1 pentru a elibera un slot (XE accepta maxim 3 user PDBs)
DECLARE
    not_exist EXCEPTION;
    PRAGMA EXCEPTION_INIT (not_exist, -65011);
    not_open  EXCEPTION;
    PRAGMA EXCEPTION_INIT (not_open, -65020);
BEGIN
    BEGIN EXECUTE IMMEDIATE 'ALTER PLUGGABLE DATABASE XEPDB1 CLOSE IMMEDIATE';
    EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN EXECUTE IMMEDIATE 'DROP PLUGGABLE DATABASE XEPDB1 INCLUDING DATAFILES';
    EXCEPTION WHEN OTHERS THEN NULL; END;
END;
/

-- Creare DISTRIBUTIE (idempotent prin verificare in v$pdbs)
DECLARE v_exists NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_exists FROM v$pdbs WHERE name = 'DISTRIBUTIE';
    IF v_exists = 0 THEN
        EXECUTE IMMEDIATE q'[
            CREATE PLUGGABLE DATABASE distributie
                ADMIN USER pdb_admin IDENTIFIED BY "ModbdSecret123"
                FILE_NAME_CONVERT = (
                    '/opt/oracle/oradata/XE/pdbseed/',
                    '/opt/oracle/oradata/XE/distributie/'
                )
        ]';
        EXECUTE IMMEDIATE 'ALTER PLUGGABLE DATABASE distributie OPEN';
    END IF;
END;
/
-- Analog pentru CATALOG si VANZARI

ALTER PLUGGABLE DATABASE distributie SAVE STATE;
ALTER PLUGGABLE DATABASE catalog     SAVE STATE;
ALTER PLUGGABLE DATABASE vanzari     SAVE STATE;

SELECT con_id, name, open_mode FROM v$pdbs ORDER BY con_id;
```

[PRINT-SCREEN 1: Output `SELECT con_id, name, open_mode FROM v$pdbs` — cele 3 PDB-uri DISTRIBUTIE / CATALOG / VANZARI cu open_mode = READ WRITE]

### 1.2 Crearea utilizatorilor aplicativi și a rolului `sgbd_role`

Scriptul `02_create_users.sql` creează tablespace-ul `USERS`, rolul `sgbd_role` cu toate grant-urile necesare, și utilizatorul aplicativ în fiecare PDB:

```sql
ALTER SESSION SET CONTAINER = DISTRIBUTIE;

-- Tablespace USERS (idempotent)
DECLARE
    tbs_exists EXCEPTION;
    PRAGMA EXCEPTION_INIT (tbs_exists, -1543);
BEGIN
    EXECUTE IMMEDIATE q'[
        CREATE TABLESPACE users
            DATAFILE '/opt/oracle/oradata/XE/distributie/users01.dbf'
            SIZE 100M AUTOEXTEND ON NEXT 50M MAXSIZE 2G
    ]';
EXCEPTION WHEN tbs_exists THEN NULL;
END;
/

ALTER DATABASE DEFAULT TABLESPACE users;

-- Cleanup utilizatori vechi (idempotent)
BEGIN EXECUTE IMMEDIATE 'DROP USER sgbd_distributie CASCADE';
EXCEPTION WHEN OTHERS THEN NULL; END;
/

-- Role sgbd_role cu grant-urile complete
DECLARE role_exists EXCEPTION; PRAGMA EXCEPTION_INIT (role_exists, -1921);
BEGIN EXECUTE IMMEDIATE 'CREATE ROLE sgbd_role';
EXCEPTION WHEN role_exists THEN NULL; END;
/

GRANT connect, resource                                 TO sgbd_role;
GRANT create table, create view, create materialized view TO sgbd_role;
GRANT create synonym, create procedure, create sequence TO sgbd_role;
GRANT create trigger, create type                       TO sgbd_role;
GRANT query rewrite, select_catalog_role, alter session TO sgbd_role;
GRANT select any dictionary                             TO sgbd_role;
GRANT create database link, create public database link TO sgbd_role;
GRANT create public synonym, create job                 TO sgbd_role;

-- User aplicativ
CREATE USER sgbd_distributie IDENTIFIED BY oracle
    DEFAULT TABLESPACE users
    QUOTA UNLIMITED ON users
    ACCOUNT UNLOCK;

GRANT sgbd_role            TO sgbd_distributie;
GRANT UNLIMITED TABLESPACE TO sgbd_distributie;

-- Repeta pentru CATALOG (sgbd_catalog) si VANZARI (sgbd_vanzari)
```

[PRINT-SCREEN 2: Output `SELECT username FROM all_users WHERE username LIKE 'SGBD%'` — cei 3 utilizatori app vizibili]

### 1.3 Director CSV pentru external tables

Scriptul `03_csv_directory.sql` creează directorul Oracle `csv_dir` în fiecare PDB:

```sql
ALTER SESSION SET CONTAINER = DISTRIBUTIE;
CREATE OR REPLACE DIRECTORY csv_dir AS '/csv';
GRANT READ ON DIRECTORY csv_dir TO sgbd_distributie;

-- Repeta pentru CATALOG si VANZARI
```

[PRINT-SCREEN 3: Output `SELECT directory_name, directory_path FROM all_directories WHERE directory_name = 'CSV_DIR'` — directorul vizibil in cele 3 PDB-uri]


## 2. Crearea relațiilor și a fragmentelor (1p, obligatoriu)

DDL-ul pentru fiecare PDB creează tabelele master, fragmentele și constrângerile locale.

### 2.1 DDL PDB DISTRIBUTIE (8 tabele master + 8 FK locale)

```sql
-- Conectare ca sgbd_distributie pe PDB DISTRIBUTIE

CREATE TABLE zone (
    id              NUMBER(19)
  , cod_zona        VARCHAR2(40)    NOT NULL
  , den_zona        VARCHAR2(80)    NOT NULL
  , tip_zona        VARCHAR2(10)    NOT NULL
  , parent_zona_id  NUMBER(19)
  , CONSTRAINT pk_zone       PRIMARY KEY (id)
  , CONSTRAINT uk_zone_cod   UNIQUE (cod_zona)
  , CONSTRAINT fk_zone_parent FOREIGN KEY (parent_zona_id) REFERENCES zone (id)
);

CREATE TABLE agenti (
    id          NUMBER(19)
  , cod_agent   VARCHAR2(20)  NOT NULL
  , nume_agent  VARCHAR2(100) NOT NULL
  , email       VARCHAR2(200)
  , CONSTRAINT pk_agenti     PRIMARY KEY (id)
  , CONSTRAINT uk_agenti_cod UNIQUE (cod_agent)
);

CREATE TABLE clienti (
    id               NUMBER(19)
  , cod_client       VARCHAR2(60)  NOT NULL
  , denumire_client  VARCHAR2(200) NOT NULL
  , tip_client       VARCHAR2(12)  NOT NULL
  , id_zona          NUMBER(19)    NOT NULL
  , start_date       DATE          NOT NULL
  , end_date         DATE
  , CONSTRAINT pk_clienti      PRIMARY KEY (id)
  , CONSTRAINT uk_clienti_cod  UNIQUE (cod_client)
  , CONSTRAINT fk_clienti_zona FOREIGN KEY (id_zona) REFERENCES zone (id)
  , CONSTRAINT ck_clienti_dates CHECK (end_date IS NULL OR end_date > start_date)
);

-- ... clienti_contacte, intervale_plata, intervale_plata_zile,
--     zone_agenti (M:N), zone_intervale_plata (M:N)
-- Vezi codul complet in Anexa, sectiunea 23.
```

[PRINT-SCREEN 4: Output `SELECT table_name FROM user_tables ORDER BY table_name` conectat ca sgbd_distributie — cele 8 tabele vizibile: AGENTI, CLIENTI, CLIENTI_CONTACTE, INTERVALE_PLATA, INTERVALE_PLATA_ZILE, ZONE, ZONE_AGENTI, ZONE_INTERVALE_PLATA]

### 2.2 DDL PDB CATALOG (lookup + fragmente verticale ITEMS_CORE/ITEMS_EXTRA)

```sql
-- Conectare ca sgbd_catalog pe PDB CATALOG

CREATE TABLE brands (
    id           NUMBER(19),
    code         VARCHAR2(3)   NOT NULL,
    brand        VARCHAR2(50),
    description  VARCHAR2(300),
    CONSTRAINT pk_brands      PRIMARY KEY (id),
    CONSTRAINT uk_brands_code UNIQUE (code)
);

-- ... items_category, items_type, items_seasons (lookup-uri)

-- Fragmentul vertical 1: identitate + clasificare (BEA cluster CORE)
CREATE TABLE items_core (
    id            NUMBER(19),
    item_code     VARCHAR2(50)    NOT NULL,
    item_name     VARCHAR2(350)   NOT NULL,
    brand_id      NUMBER(19),
    season_id     NUMBER(19),
    item_type_id  NUMBER(19),
    category_id   NUMBER(19),
    active        NUMBER,
    CONSTRAINT pk_items_core      PRIMARY KEY (id),
    CONSTRAINT uk_items_code      UNIQUE (item_code),
    CONSTRAINT fk_items_brand     FOREIGN KEY (brand_id)     REFERENCES brands(id),
    CONSTRAINT fk_items_category  FOREIGN KEY (category_id)  REFERENCES items_category(id),
    CONSTRAINT fk_items_type      FOREIGN KEY (item_type_id) REFERENCES items_type(id),
    CONSTRAINT fk_items_season    FOREIGN KEY (season_id)    REFERENCES items_seasons(id)
);

-- Fragmentul vertical 2: atribute comerciale + fizice (BEA cluster EXTRA)
-- Cheie 1:1 cu items_core (ON DELETE CASCADE)
CREATE TABLE items_extra (
    id                NUMBER(19),
    item_description  VARCHAR2(1000),
    vat               BINARY_DOUBLE,
    last_cost_price   NUMBER(9, 2),
    main_barcode      VARCHAR2(20),
    supplier_code     VARCHAR2(60),
    weight            NUMBER(9, 2),
    um                VARCHAR2(10),
    CONSTRAINT pk_items_extra     PRIMARY KEY (id),
    CONSTRAINT fk_items_extra_core FOREIGN KEY (id) REFERENCES items_core (id) ON DELETE CASCADE
);
```

[PRINT-SCREEN 5: Output `SELECT table_name FROM user_tables ORDER BY table_name` conectat ca sgbd_catalog — vezi BRANDS, ITEMS_CATEGORY, ITEMS_CORE, ITEMS_EXTRA, ITEMS_SEASONS, ITEMS_TYPE]

### 2.3 DDL PDB VANZARI (4 fragmente fizice orizontale)

Conform algoritmului COM_MIN aplicat pe `FISE_CLIENTI` (sec. 4.1 din raport), tabela se materializează ca două fragmente fizice cu CHECK constraint pe predicatul de fragmentare:

```sql
-- Fragmentul orizontal 1: moneda = 'RON'
CREATE TABLE fise_clienti_ro (
    id                  NUMBER(19),
    nr_document         VARCHAR2(30)  NOT NULL,
    doc_type_xrp        CHAR(3)       NOT NULL,
    tip_doc             CHAR(1)       NOT NULL,
    data_doc_efectiva   DATE          NOT NULL,
    moneda              VARCHAR2(10)  NOT NULL,
    amount_doc          NUMBER(17, 2) NOT NULL,
    -- ... restul coloanelor
    cod_client          VARCHAR2(60)  NOT NULL,
    CONSTRAINT pk_fise_ro    PRIMARY KEY (id),
    CONSTRAINT uk_fise_ro_doc UNIQUE (nr_document, doc_type_xrp),
    CONSTRAINT ck_fise_ro_mon CHECK (moneda = 'RON'),
    CONSTRAINT ck_fise_ro_tipdoc CHECK (tip_doc IN ('F','I'))
);

-- Fragmentul orizontal 2: moneda <> 'RON' (EUR + CZK + USD)
CREATE TABLE fise_clienti_ext (
    -- identic structural cu fise_clienti_ro
    -- DIFERENTA: CHECK ck_fise_ext_mon CHECK (moneda <> 'RON')
);

-- Fragmentare derivata pe LINII_DOC (semijoin cu owner FISE)
CREATE TABLE linii_doc_ro (
    id            NUMBER(19),
    doc_type_xrp  CHAR(3)       NOT NULL,
    nr_document   VARCHAR2(30)  NOT NULL,
    item_code     VARCHAR2(50)  NOT NULL,
    -- ... restul coloanelor
    CONSTRAINT pk_lin_ro PRIMARY KEY (id),
    CONSTRAINT fk_lin_ro_fise FOREIGN KEY (nr_document, doc_type_xrp)
        REFERENCES fise_clienti_ro (nr_document, doc_type_xrp)
);

CREATE TABLE linii_doc_ext (
    -- identic, FK -> fise_clienti_ext
);
```

[PRINT-SCREEN 6: Output `SELECT table_name FROM user_tables` conectat ca sgbd_vanzari — vezi FISE_CLIENTI_RO, FISE_CLIENTI_EXT, LINII_DOC_RO, LINII_DOC_EXT]


## 3. Popularea cu date (0.5p, obligatoriu)

Datele se încarcă din cele 15 fișiere CSV anonimizate prin external tables (driver `ORACLE_LOADER`). Pentru fragmentele orizontale, INSERT-ul folosește un filtru pe `Moneda` care realizează split-ul automat:

```sql
-- Definire external table peste CSV
CREATE TABLE ext_docs_headers (
    Id NUMBER(19),
    NrDocument VARCHAR2(30),
    Moneda VARCHAR2(10),
    -- ... coloane corespunzatoare CSV-ului
)
ORGANIZATION EXTERNAL (
    TYPE              ORACLE_LOADER
    DEFAULT DIRECTORY csv_dir
    ACCESS PARAMETERS (
        RECORDS DELIMITED BY NEWLINE
        CHARACTERSET UTF8
        NOLOGFILE NOBADFILE NODISCARDFILE
        SKIP 1
        FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LRTRIM
        MISSING FIELD VALUES ARE NULL
    )
    LOCATION ('DOCS_HEADERS.csv')
) REJECT LIMIT UNLIMITED;

-- INSERT cu split pe Moneda: fragmente RO + EXT alimentate dintr-un singur SELECT
INSERT INTO fise_clienti_ro (id, nr_document, ..., moneda, ...)
SELECT Id, NrDocument, ..., Moneda, ...
FROM   ext_docs_headers
WHERE  Moneda = 'RON';

INSERT INTO fise_clienti_ext (id, nr_document, ..., moneda, ...)
SELECT Id, NrDocument, ..., Moneda, ...
FROM   ext_docs_headers
WHERE  Moneda <> 'RON';

COMMIT;
DROP TABLE ext_docs_headers;
```

[PRINT-SCREEN 7: SELECT-uri de verificare cu counts]

```sql
-- Verificare volume incarcate (rulat in sgbd_vanzari@VANZARI)
SELECT 'fise_clienti_ro'  AS tabela, COUNT(*) AS randuri FROM fise_clienti_ro UNION ALL
SELECT 'fise_clienti_ext',          COUNT(*)             FROM fise_clienti_ext UNION ALL
SELECT 'linii_doc_ro',              COUNT(*)             FROM linii_doc_ro UNION ALL
SELECT 'linii_doc_ext',             COUNT(*)             FROM linii_doc_ext;
-- Rezultat asteptat:
--   fise_clienti_ro     1555
--   fise_clienti_ext     493
--   linii_doc_ro        3806
--   linii_doc_ext       1712
```


## 4. Furnizarea formelor de transparență (2.5p)

### 4.1 Transparență verticală pentru fragmentarea BEA pe ITEMS (1p)

View-ul `V_ITEMS` face JOIN între `ITEMS_CORE` și `ITEMS_EXTRA`, expunând toate cele 15 coloane originale ale ITEMS:

```sql
CREATE OR REPLACE VIEW v_items (
    id, item_code, item_name, item_description,
    brand_id, season_id, item_type_id, category_id,
    vat, last_cost_price, main_barcode, supplier_code,
    weight, um, active
) AS
SELECT
    c.id, c.item_code, c.item_name, e.item_description,
    c.brand_id, c.season_id, c.item_type_id, c.category_id,
    e.vat, e.last_cost_price, e.main_barcode, e.supplier_code,
    e.weight, e.um, c.active
FROM   items_core c
       JOIN items_extra e ON e.id = c.id;
```

Triggere INSTEAD OF pentru DML transparent:

```sql
CREATE OR REPLACE TRIGGER trg_v_items_ins
INSTEAD OF INSERT ON v_items
FOR EACH ROW
BEGIN
    INSERT INTO items_core (id, item_code, item_name, brand_id, season_id, item_type_id, category_id, active)
    VALUES (:NEW.id, :NEW.item_code, :NEW.item_name, :NEW.brand_id, :NEW.season_id,
            :NEW.item_type_id, :NEW.category_id, :NEW.active);

    INSERT INTO items_extra (id, item_description, vat, last_cost_price,
                             main_barcode, supplier_code, weight, um)
    VALUES (:NEW.id, :NEW.item_description, :NEW.vat, :NEW.last_cost_price,
            :NEW.main_barcode, :NEW.supplier_code, :NEW.weight, :NEW.um);
END;
/

-- Triggere similare pentru INSTEAD OF UPDATE si INSTEAD OF DELETE
```

[PRINT-SCREEN 8: `SELECT * FROM v_items WHERE ROWNUM <= 5` — afișează rândurile unificate cu cele 15 coloane originale ITEMS]

[PRINT-SCREEN 9: Demo INSERT V_ITEMS — `INSERT INTO v_items VALUES (...)` apoi `SELECT COUNT(*) FROM items_core WHERE id = X` și `SELECT COUNT(*) FROM items_extra WHERE id = X` — ambele returnează 1, confirmând că trigger-ul a împărțit insertul în ambele fragmente]

### 4.2 Transparență orizontală pentru FISE_CLIENTI și LINII_DOC (1p)

```sql
CREATE OR REPLACE VIEW v_fise_clienti (
    id, nr_document, nr_doc_initial, tip_doc, doc_type_xrp,
    data_doc_efectiva, data_scad, semn, moneda,
    amount_doc, amount_doc_ron, plata_prin,
    cod_client, denumire_client, clasa_client
) AS
SELECT id, nr_document, nr_doc_initial, tip_doc, doc_type_xrp,
       data_doc_efectiva, data_scad, semn, moneda,
       amount_doc, amount_doc_ron, plata_prin,
       cod_client, denumire_client, clasa_client
FROM   fise_clienti_ro

UNION ALL

SELECT id, nr_document, nr_doc_initial, tip_doc, doc_type_xrp,
       data_doc_efectiva, data_scad, semn, moneda,
       amount_doc, amount_doc_ron, plata_prin,
       cod_client, denumire_client, clasa_client
FROM   fise_clienti_ext;

-- Analog pentru V_LINII_DOC

-- Trigger INSTEAD OF INSERT ruteaza dupa moneda
CREATE OR REPLACE TRIGGER trg_v_fise_ins
INSTEAD OF INSERT ON v_fise_clienti
FOR EACH ROW
BEGIN
    IF :NEW.moneda = 'RON' THEN
        INSERT INTO fise_clienti_ro VALUES (:NEW.id, :NEW.nr_document, ...);
    ELSE
        INSERT INTO fise_clienti_ext VALUES (:NEW.id, :NEW.nr_document, ...);
    END IF;
END;
/

-- 4 alte triggere: UPDATE pe v_fise (cu migrare cross-fragment daca moneda
-- se schimba intre RON si non-RON), DELETE pe v_fise, INSERT si DELETE pe v_linii.
```

[PRINT-SCREEN 10: `SELECT COUNT(*) FROM v_fise_clienti` = 2.048 = suma 1.555 (RO) + 493 (EXT) — transparență orizontală confirmată]

[PRINT-SCREEN 11: Demo INSERT V_FISE_CLIENTI cu moneda='RON' apoi `SELECT * FROM fise_clienti_ro WHERE id = X` — rândul apare în fragmentul RO]

[PRINT-SCREEN 12: Demo INSERT V_FISE_CLIENTI cu moneda='EUR' apoi `SELECT * FROM fise_clienti_ext WHERE id = Y` — rândul apare în fragmentul EXT]

### 4.3 Transparență cross-PDB prin DB Links + MV-uri replicate (0.5p)

DB Links private inițiate de VANZARI spre celelalte 2 PDB-uri:

```sql
-- Conectare ca sgbd_vanzari pe VANZARI
CREATE DATABASE LINK lnk_distributie
    CONNECT TO sgbd_distributie IDENTIFIED BY oracle
    USING 'localhost:1521/DISTRIBUTIE';

CREATE DATABASE LINK lnk_catalog
    CONNECT TO sgbd_catalog IDENTIFIED BY oracle
    USING 'localhost:1521/CATALOG';
```

Cele 7 Materialized Views replicate ca REFRESH FAST ON DEMAND:

```sql
CREATE MATERIALIZED VIEW mv_clienti
    BUILD IMMEDIATE REFRESH FAST ON DEMAND WITH PRIMARY KEY
    AS SELECT * FROM clienti@lnk_distributie;

ALTER TABLE mv_clienti ADD CONSTRAINT uk_mv_clienti_cod UNIQUE (cod_client);

-- Analog pentru mv_zone (din distributie), mv_items_core, mv_brands,
-- mv_items_category, mv_items_type, mv_items_seasons (din catalog)
```

[PRINT-SCREEN 13: `SELECT * FROM clienti@lnk_distributie WHERE ROWNUM <= 5` — citire remote prin DB link]

[PRINT-SCREEN 14: `SELECT * FROM mv_clienti WHERE ROWNUM <= 5` — același rezultat, dar din replica locală în VANZARI]


## 5. Sincronizarea relațiilor replicate (1p)

MV LOGs instalate pe tabelele master (în DISTRIBUTIE + CATALOG) captează modificările incremental:

```sql
-- Rulate ca SYS, alternand intre PDB-uri prin ALTER SESSION
ALTER SESSION SET CONTAINER = DISTRIBUTIE;
ALTER SESSION SET CURRENT_SCHEMA = sgbd_distributie;
CREATE MATERIALIZED VIEW LOG ON clienti WITH PRIMARY KEY, ROWID, SEQUENCE INCLUDING NEW VALUES;
CREATE MATERIALIZED VIEW LOG ON zone    WITH PRIMARY KEY, ROWID, SEQUENCE INCLUDING NEW VALUES;

ALTER SESSION SET CONTAINER = CATALOG;
ALTER SESSION SET CURRENT_SCHEMA = sgbd_catalog;
CREATE MATERIALIZED VIEW LOG ON items_core     WITH PRIMARY KEY, ROWID, SEQUENCE INCLUDING NEW VALUES;
CREATE MATERIALIZED VIEW LOG ON brands         WITH PRIMARY KEY, ROWID, SEQUENCE INCLUDING NEW VALUES;
CREATE MATERIALIZED VIEW LOG ON items_category WITH PRIMARY KEY, ROWID, SEQUENCE INCLUDING NEW VALUES;
CREATE MATERIALIZED VIEW LOG ON items_type     WITH PRIMARY KEY, ROWID, SEQUENCE INCLUDING NEW VALUES;
CREATE MATERIALIZED VIEW LOG ON items_seasons  WITH PRIMARY KEY, ROWID, SEQUENCE INCLUDING NEW VALUES;
```

Job DBMS_SCHEDULER care propagă delta-ul la 60 secunde:

```sql
BEGIN
    DBMS_SCHEDULER.CREATE_JOB(
        job_name        => 'JOB_REFRESH_MVS',
        job_type        => 'PLSQL_BLOCK',
        job_action      => 'BEGIN DBMS_MVIEW.REFRESH(
            ''MV_CLIENTI,MV_ZONE,MV_ITEMS_CORE,MV_BRANDS,MV_ITEMS_CATEGORY,MV_ITEMS_TYPE,MV_ITEMS_SEASONS'',
            method => ''FFFFFFF'', atomic_refresh => FALSE); END;',
        start_date      => SYSTIMESTAMP,
        repeat_interval => 'FREQ=SECONDLY;INTERVAL=60',
        enabled         => TRUE,
        comments        => 'Refresh FAST al MV-urilor replicate la 60s');
END;
/
```

[PRINT-SCREEN 15: Demo sincronizare end-to-end — 1) conectat la DISTRIBUTIE: `INSERT INTO clienti (...) VALUES (999, 'CLI_TEST', ...); COMMIT;`. 2) Conectat la VANZARI: `SELECT COUNT(*) FROM mv_clienti` returnează valoarea veche. 3) `BEGIN DBMS_MVIEW.REFRESH('MV_CLIENTI', method => 'F'); END; /`. 4) `SELECT COUNT(*) FROM mv_clienti` — acum returnează valoarea nouă]

[PRINT-SCREEN 16: `SELECT job_name, enabled, state, run_count FROM user_scheduler_jobs WHERE job_name = 'JOB_REFRESH_MVS'` — confirmă că job-ul rulează]


## 6. Asigurarea constrângerilor de integritate (2p, obligatoriu)

### 6.1 Constrângeri locale (definite în DDL)

Toate constrângerile UK, PK, FK, CHECK din tabelele master și fragmentele fizice sunt declarate inline la `CREATE TABLE`. Pentru sumar:

[PRINT-SCREEN 17: `SELECT constraint_name, constraint_type, table_name FROM user_constraints WHERE constraint_type IN ('P','U','R','C') ORDER BY table_name, constraint_type` — lista exhaustivă de constrângeri locale per PDB]

### 6.2 Constrângeri cross-PDB (FK către MV-uri replicate)

4 chei externe care leagă fact tables din VANZARI de MV-urile replicate (cod_client + item_code):

```sql
ALTER TABLE fise_clienti_ro
    ADD CONSTRAINT fk_fise_ro_client FOREIGN KEY (cod_client) REFERENCES mv_clienti (cod_client);

ALTER TABLE fise_clienti_ext
    ADD CONSTRAINT fk_fise_ext_client FOREIGN KEY (cod_client) REFERENCES mv_clienti (cod_client);

ALTER TABLE linii_doc_ro
    ADD CONSTRAINT fk_lin_ro_item FOREIGN KEY (item_code) REFERENCES mv_items_core (item_code);

ALTER TABLE linii_doc_ext
    ADD CONSTRAINT fk_lin_ext_item FOREIGN KEY (item_code) REFERENCES mv_items_core (item_code);
```

[PRINT-SCREEN 18: Demo FK enforcement — `INSERT INTO fise_clienti_ro (..., cod_client) VALUES (..., 'CLIENT_INEXISTENT')` → eroare `ORA-02291: integrity constraint (SGBD_VANZARI.FK_FISE_RO_CLIENT) violated - parent key not found`]

### 6.3 Constrângere cu agregat (curs cap. 3.4 clasa 3)

Trigger AFTER STATEMENT pe LINII_DOC verifică coerența `amount_doc = SUM(linie.valoare + linie.tva)` cu toleranță 0.01:

```sql
CREATE OR REPLACE TRIGGER trg_coerenta_sum_ro
AFTER INSERT OR UPDATE OR DELETE ON linii_doc_ro
DECLARE
    CURSOR c IS
        SELECT  f.nr_document, f.doc_type_xrp,
                f.amount_doc                                              AS doc_total,
                SUM(l.xrp_linie_valoare_fara_tva + l.xrp_linie_tva)       AS sum_linii
        FROM    fise_clienti_ro f
                JOIN linii_doc_ro l
                     ON  l.nr_document  = f.nr_document
                     AND l.doc_type_xrp = f.doc_type_xrp
        GROUP BY f.nr_document, f.doc_type_xrp, f.amount_doc
        HAVING  ABS(f.amount_doc - SUM(l.xrp_linie_valoare_fara_tva + l.xrp_linie_tva)) > 0.01;
BEGIN
    FOR r IN c LOOP
        RAISE_APPLICATION_ERROR(-20001,
            'Incoerenta suma pe ' || r.nr_document || '/' || r.doc_type_xrp ||
            ' (doc=' || r.doc_total || ' vs sum_linii=' || r.sum_linii || ')');
    END LOOP;
END;
/

-- Trigger similar (trg_coerenta_sum_ext) pe fragmentul EXT
```

[PRINT-SCREEN 19: Demo trigger — INSERT linie cu sumă greșită → `ORA-20001: Incoerenta suma pe ... (doc=X vs sum_linii=Y)`]


## 7. Optimizarea cererii SQL complexe (1.5p)

Cererea complexă „top 10 agenți după valoare vândută în 2024, defalcat pe zonă și categorie" (formulată în PARTEA I, sec. 9) este optimizată prin compararea a 3 planuri de execuție.

### 7.1 Plan RBO (Rule-Based Optimizer) --- 0.5p

```sql
EXPLAIN PLAN SET STATEMENT_ID = 'Q_RBO' FOR
SELECT /*+ RULE */
    a.nume_agent, z.den_zona, c.name AS categorie,
    SUM(ld.xrp_linie_valoare_fara_tva) AS total_2024
FROM v_fise_clienti f
     JOIN v_linii_doc ld   ON ld.nr_document = f.nr_document AND ld.doc_type_xrp = f.doc_type_xrp
     JOIN mv_clienti cli   ON cli.cod_client = f.cod_client
     JOIN mv_zone z        ON z.id = cli.id_zona
     JOIN zone_agenti@lnk_distributie za
            ON za.id_zona = cli.id_zona
           AND f.data_doc_efectiva BETWEEN za.start_date AND NVL(za.end_date, DATE '9999-12-31')
     JOIN agenti@lnk_distributie a   ON a.id = za.id_agent
     JOIN mv_items_core ic           ON ic.item_code = ld.item_code
     JOIN mv_items_category c        ON c.id = ic.category_id
WHERE f.tip_doc = 'F'
  AND f.data_doc_efectiva >= DATE '2024-01-01'
  AND f.data_doc_efectiva <  DATE '2025-01-01'
GROUP BY a.nume_agent, z.den_zona, c.name
ORDER BY total_2024 DESC
FETCH FIRST 10 ROWS ONLY;

SELECT plan_table_output FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, 'Q_RBO', 'BASIC +ROWS +COST'));
```

[PRINT-SCREEN 20: Plan RBO complet în DBeaver mod Text (47 operații, hash 2771358336, fără coloane Rows/Cost)]

**Explicație etape parcurse**: optimizatorul bazat pe regulă (activat prin hint `/*+ RULE */`) ignoră statisticile și aplică reguli fixe. Decizii cheie:

1. **REMOTE pentru AGENTI și ZONE_AGENTI** (operațiile 38, 40) --- citește integral tabele remote prin DB link, fără filtre pushed-down la nivel de sursă.
2. **TABLE ACCESS BY INDEX ROWID** pentru fragmentele FISE_CLIENTI_RO/EXT (28, 30) prin INDEX RANGE SCAN pe `IDX_FISE_*_TIP` --- RBO preferă orice index disponibil indiferent de selectivitate.
3. **MAT_VIEW ACCESS BY INDEX ROWID** pentru MV_CLIENTI, MV_ITEMS_CORE, MV_ZONE, MV_ITEMS_CATEGORY (21, 24, 32, 35) cu lookup prin index unique.
4. **MERGE JOIN** + **NESTED LOOPS** alternative pentru toate join-urile, fără să evalueze cardinalitatea.

RBO **nu poate evalua costul** planului --- nu există coloane Rows/Cost în output. Aceasta este o limitare fundamentală: deciziile sunt pe baza priorității regulilor, nu pe baza dimensiunilor reale ale datelor.

### 7.2 Plan CBO default --- 0.5p

```sql
EXPLAIN PLAN SET STATEMENT_ID = 'Q_CBO' FOR
SELECT a.nume_agent, z.den_zona, c.name AS categorie,
       SUM(ld.xrp_linie_valoare_fara_tva) AS total_2024
FROM v_fise_clienti f
     JOIN v_linii_doc ld ON ld.nr_document = f.nr_document AND ld.doc_type_xrp = f.doc_type_xrp
     -- ... acelasi query, fara /*+ RULE */
;

SELECT plan_table_output FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, 'Q_CBO', 'BASIC +ROWS +COST'));
```

[PRINT-SCREEN 21: Plan CBO complet (36 operații, hash 2214986998, **cost total 70**)]

**Explicație etape parcurse**: optimizatorul bazat pe cost folosește statistici colectate prin `DBMS_STATS.GATHER_SCHEMA_STATS` și estimează cardinalitatea fiecărei operații. Decizii cheie:

1. **HASH JOIN dominant** (operațiile 5, 8, 9, 10, 11) --- CBO știe că fact tables-urile sunt mici (~2.048 documente, ~5.518 linii), deci construirea unui hash table e mai eficientă decât NESTED LOOPS.
2. **TABLE ACCESS FULL pe FISE_CLIENTI_RO/EXT** (20, 21) cu cost 9 și 5 --- CBO calculează că scan complet e mai ieftin decât index range scan pe fragmente atât de mici.
3. **REMOTE pentru ZONE_AGENTI și AGENTI** (17, 22) --- CBO păstrează accesul remote dar îl plasează strategic după filtrele pe FISE.
4. **MAT_VIEW ACCESS FULL pe MV_ITEMS_CATEGORY** (29) --- doar 15 rânduri, scan complet trivial.

Costul total estimat este **70 unități de I/O abstracte**.

### 7.3 Sugestii de optimizare --- plan CBO cu DRIVING_SITE --- 0.5p

Aplicând hint-ul `/*+ DRIVING_SITE(a) */`, instruim optimizatorul să **asambleze rezultatul pe nodul DISTRIBUTIE** (unde se află `AGENTI` și `ZONE_AGENTI`):

```sql
EXPLAIN PLAN SET STATEMENT_ID = 'Q_CBO_DS' FOR
SELECT /*+ DRIVING_SITE(a) */
    a.nume_agent, z.den_zona, c.name AS categorie,
    SUM(ld.xrp_linie_valoare_fara_tva) AS total_2024
FROM v_fise_clienti f
     JOIN agenti@lnk_distributie a ON a.id = za.id_agent
     -- ... acelasi query
;

SELECT plan_table_output FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, 'Q_CBO_DS', 'BASIC +ROWS +COST'));
```

[PRINT-SCREEN 22: Plan CBO + DRIVING_SITE complet (hash 2030687216, **cost total 46**)]

**Explicație etape parcurse**:

1. **`SELECT STATEMENT REMOTE`** (operația 0) --- întreaga execuție migrează în DISTRIBUTIE. Datele din VANZARI (fact tables, MV-uri) sunt trimise spre DISTRIBUTIE prin DB link, iar agregarea finală + ordonarea se fac acolo.
2. **Reducere de cost de la 70 la 46** = **34% îmbunătățire**. Sursa principală: `AGENTI` și `ZONE_AGENTI` nu mai sunt accesate REMOTE (sunt locale pe DISTRIBUTIE), iar volumul transferat e mai mic decât în varianta default.
3. **WINDOW SORT PUSHED RANK** mutat în sub-planul remote (operația 3) --- top-10 e calculat înainte de transfer, nu după.

Această variantă confirmă teoria SDD-1 din cap. 5 din curs: minimizarea volumului transportat pe rețea prin alegerea inteligentă a site-ului de asamblare.

### 7.4 Tabel comparativ

| Plan | Plan hash | Cost total | Operații dominante | Observație |
|---|---|---|---|---|
| **RBO** (`/*+ RULE */`) | 2771358336 | N/A | MERGE JOIN + NESTED LOOPS | Nu evaluează volumele; folosește orice index |
| **CBO default** | 2214986998 | 70 | HASH JOIN + TABLE FULL | Folosește statistici fresh DBMS_STATS |
| **CBO + DRIVING_SITE(a)** | 2030687216 | **46** | Assembly remote pe DISTRIBUTIE | **Câștigător: −34% cost** |

**Concluzie**: pentru această cerere distribuită, `DRIVING_SITE(a)` e tehnica cea mai eficientă. Optimizatorul ar fi putut alege această strategie automat dacă ar fi avut statistici proaspete și cross-database --- în practică, hint-ul rămâne util ca semnal expert pentru cazuri specifice.

\newpage

# PARTEA III --- APLICAȚIA FRONT-END (MODULUL 3)

[A SE COMPLETA: aplicația lui Ștefan Măgureanu]

## 1. Arhitectura aplicației

[INSEREAZĂ: stack tehnologic ales — framework (React/Vue/Angular/Express/etc.), driver Oracle folosit (oracledb pentru Node.js, JDBC pentru Java, cx_Oracle pentru Python, etc.), pattern de conexiuni la cele 3 PDB-uri]

[DIAGRAMĂ: arhitectura aplicației — componente UI ↔ Backend API ↔ 3 PDB-uri Oracle (DB Pool)]

## 2. Modul CRUD pe BD-urile locale (3p)

[PRINT-SCREEN A1: interfața de listare clienți din PDB DISTRIBUTIE]
[PRINT-SCREEN A2: formular creare client nou + confirmare în BD]
[PRINT-SCREEN A3: editare client existent (UPDATE) + confirmare]
[PRINT-SCREEN A4: ștergere client (DELETE) + verificare cascade FK]
[PRINT-SCREEN A5: listare produse din PDB CATALOG (via V_ITEMS pentru transparență verticală)]
[PRINT-SCREEN A6: listare documente din PDB VANZARI (via V_FISE_CLIENTI pentru transparență orizontală)]

## 3. Modul de vizualizare la nivelul BD globale (1p)

[PRINT-SCREEN A7: dashboard care arată date din toate cele 3 PDB-uri prin view-urile de transparență. Aplicația tratează datele ca și cum nu ar fi distribuite — toate query-urile sunt prin V_FISE_CLIENTI, V_LINII_DOC, V_ITEMS și MV-urile replicate.]

## 4. Vizualizarea globală a operațiilor LMD locale (2p)

Demo flow: modificarea făcută direct într-un fragment (prin DBeaver, ca administrator) se reflectă în interfața globală.

[PRINT-SCREEN A8: aplicația arată documentul X cu valoarea V]
[PRINT-SCREEN A9: în DBeaver, conectat ca sgbd_vanzari, rulează `UPDATE fise_clienti_ro SET amount_doc = V' WHERE id = ...`]
[PRINT-SCREEN A10: aplicația, după refresh, arată documentul X cu valoarea V' --- propagarea local → global funcționează]

## 5. Verificarea propagării LMD global → local (3p)

Demo flow: operațiunile prin view-urile de transparență din aplicație ajung corect în fragmentele fizice.

[PRINT-SCREEN A11: aplicația --- INSERT document nou cu moneda='RON' prin V_FISE_CLIENTI]
[PRINT-SCREEN A12: în DBeaver --- `SELECT * FROM fise_clienti_ro WHERE id = ...` --- rândul apare în fragmentul RO, dar nu și în EXT]
[PRINT-SCREEN A13: aplicația --- INSERT document nou cu moneda='EUR' prin V_FISE_CLIENTI]
[PRINT-SCREEN A14: în DBeaver --- `SELECT * FROM fise_clienti_ext WHERE id = ...` --- rândul apare în fragmentul EXT, dar nu și în RO]

Aceste demonstrații confirmă funcționarea corectă a triggerelor `INSTEAD OF` care realizează rutarea automată pe baza predicatului de fragmentare.

\newpage

# PARTEA IV --- ANEXE

## A. Componența echipei și distribuția task-urilor

[INSEREAZĂ AICI conținutul din SOP_X_Echipa.docx --- detaliază contribuția fiecărui membru pe cele 3 module]

## B. Codul sursă SQL/PL-SQL complet

Codul SQL/PL-SQL al întregului proiect este structurat în 4 fișiere de lucru și un fișier consolidat pentru livrare. Pentru detalii vezi fișierul anexă `SOP_X_Sursa.txt` (livrat separat conform cerinței 4 din baremul de submisie).

Structura cod (rezumată):

- **`Setup.sql`** (54 KB, ~1740 linii): bootstrap one-time --- PDB-uri, utilizatori, DDL pentru toate tabelele master + fragmente, populare cu date din 15 CSV-uri.
- **`Demo_Schema.sql`** (40 KB, ~1280 linii): re-rulabil oricând --- layerul de transparență (V_ITEMS, V_FISE_CLIENTI, V_LINII_DOC + 8 INSTEAD OF triggere), MV LOGs, DB links, 7 MV-uri replicate, 4 FK cross-PDB, job DBMS_SCHEDULER @ 60s, 2 triggere agregat coerență sume, 8 indecși.
- **`Demo_Queries.sql`** (13 KB, ~400 linii): cererea SQL complexă + 3 EXPLAIN PLAN (RBO / CBO / CBO+DRIVING_SITE) + 5 teste end-to-end de validare.
- **`SOP_X_Sursa.txt`** (106 KB, ~3340 linii): consolidarea celor 3 fișiere într-un singur livrabil sqlplus-runnable.

## C. Notă de transparență privind utilizarea AI

[Se preia conținutul integral al notei AI din PARTEA I, sec. 10.2 (Andrei Pițoiu) sau se sintetizează pentru ansamblul proiectului]

