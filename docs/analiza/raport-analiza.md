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

<!-- Conținut Task 10. Punctaj: 1p (0.5p E-R + 0.5p conceptuală), ambele obligatorii. -->

## 2.1. Diagrama Entitate–Relație

## 2.2. Diagrama conceptuală

## 2.3. Justificarea normalizării (Forma Normală 3)

# 3. Modul de distribuire a datelor

<!-- Conținut Task 11. Punctaj: 0.25p obligatoriu. -->

# 4. Argumentarea deciziei de fragmentare

<!-- Conținut Task 12. Punctaj: 3p (1p H primară + 0.5p H derivată + 1p V); H primară și H derivată au obținerea fragmentelor obligatorie. -->

## 4.1. Fragmentare orizontală primară pe FISE_CLIENTI

### 4.1.1. Workload și predicate candidate

### 4.1.2. Aplicarea algoritmului COM_MIN

### 4.1.3. Fragmentele orizontale primare obținute

## 4.2. Fragmentare orizontală derivată pe LINII_DOC

### 4.2.1. Legătura între relații prin cheie compusă

### 4.2.2. Fragmentele orizontale derivate obținute

## 4.3. Fragmentare verticală pe ITEMS (algoritmul BEA)

### 4.3.1. Workload și matricea de utilizare a atributelor

### 4.3.2. Aplicarea algoritmului BEA și algoritmul PART

### 4.3.3. Fragmentele verticale obținute

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
