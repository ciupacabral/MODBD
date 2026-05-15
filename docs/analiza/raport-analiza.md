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

<!-- Conținut Task 9. Punctaj: 0.25p obligatoriu. -->

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
