# Scenariu de Prezentare — Modulul Front-End (MODBD)

Acest document este un ghid pas cu pas pe care îl poți folosi în timpul prezentării proiectului pentru a demonstra că aplicația ta acoperă toate cele 4 cerințe (10 puncte) de la implementarea Front-End.

Înainte de a începe, asigură-te că:
1. Ai pornit baza de date Oracle în Docker (`docker start oracle-modbd`).
2. Ai pornit API-ul din terminal cu `dotnet run` (în folderul `modbd/api`).
3. Ai deschis interfața web `index.html` în browser.

---

## 📍 Cerința 1: Management la nivelul bazelor de date locale (3p)
**Obiectiv:** Demonstrarea capacității de a face operații CRUD direct pe nodurile locale, fără a trece prin view-uri globale de fragmentare.

### 1.1 — CRUD Clienți (PDB DISTRIBUȚIE)
1. Deschide tab-ul **Local: Distribuție**.
2. Arată profesorului tabelul populat cu date din tabelul local `CLIENTI`.
3. **INSERT:** Folosește formularul **Adaugă Client** din dreapta:
   - Cod: `CLI999`, Nume: `Client Test Local`, Tip: `CLIENT`, Zonă: alege din dropdown
4. Apasă **Salvează**. Caută `CLI999` în bara de căutare — clientul apare instant.
5. **UPDATE:** Apasă butonul ✏️ de pe rândul tocmai creat. Formularul se populează automat.
   - Modifică numele în `Client Modificat`. Apasă **Salvează**.
6. **DELETE:** Apasă butonul 🗑️ de pe un rând. Confirmă ștergerea.

### 1.2 — Vizualizare Fragmente Verticale (PDB CATALOG)
1. Deschide tab-ul **Local: Catalog**.
2. Arată profesorului cele 2 tabele **side-by-side**: `ITEMS_CORE` (stânga) și `ITEMS_EXTRA` (dreapta).
3. Explică: aceste 2 tabele sunt fragmentarea verticală a tabelului logic `ITEMS` — CORE conține identitatea (cod, nume), EXTRA conține atributele comerciale (TVA, preț, barcode).
4. Observă că **același ID** apare în ambele tabele — demonstrează relația 1:1.

### 1.3 — Vizualizare Fragmente Orizontale (PDB VÂNZĂRI)
1. Deschide tab-urile **Local: Vânzări RO** și **Local: Vânzări EXT** (pe rând).
2. Arată profesorului că fragmentul RO conține **doar facturi în RON** (predicat: `CHECK moneda = 'RON'`).
3. Arată că fragmentul EXT conține **doar facturi în EUR/USD/CZK** (predicat: `CHECK moneda <> 'RON'`).
4. Folosește bara de căutare pentru a găsi un document specific.

---

## 📍 Cerința 2: Vizualizare la nivelul bazei de date globale (1p)
**Obiectiv:** Demonstrarea capacității aplicației de a afișa date unificate, obținute din combinarea mai multor baze de date locale (Transparență).

### 2.1 — Produse (V_ITEMS — transparență verticală)
1. Deschide tab-ul **Global: Produse**.
2. Explică: view-ul `V_ITEMS` face un **JOIN** între `ITEMS_CORE` și `ITEMS_EXTRA`, reconstituind tabelul logic complet.
3. Navighează prin pagini — toate cele 15 coloane originale sunt disponibile.

### 2.2 — Facturi (V_FISE_CLIENTI — transparență orizontală)
1. Deschide tab-ul **Global: Facturi**.
2. Explică: view-ul `V_FISE_CLIENTI` face un **UNION ALL** între `fise_clienti_ro` și `fise_clienti_ext`.
3. Arată că aici apar **toate** facturile (RON + EUR + USD), unificate.

### 2.3 — Linii Documente (V_LINII_DOC — fragment derivat)
1. Deschide tab-ul **Global: Linii Doc**.
2. Explică: view-ul `V_LINII_DOC` face un UNION ALL între `linii_doc_ro` și `linii_doc_ext` (fragment orizontal derivat).

---

## 📍 Cerința 3: Vizualizare la nivel global a operațiilor LMD locale (2p)
**Obiectiv:** Demonstrarea faptului că modificările locale se reflectă automat la nivel global.

### 3.1 — Fragment Orizontal: LMD local → vizibil în V_FISE_CLIENTI
1. Deschide tab-ul **Global: Facturi** și lasă-l deschis.
2. Deschide SQL Developer pe `PDB_VANZARI` și rulează:
   ```sql
   INSERT INTO fise_clienti_ro (id, nr_document, tip_doc, doc_type_xrp, data_doc_efectiva, semn,
                                moneda, amount_doc, amount_doc_ron, cod_client, denumire_client, clasa_client)
   VALUES (9999, 'DOC-LOCAL-1', 'F', 'INV', SYSDATE, 1,
           'RON', 500, 500, 'CLI000009', 'Iota Boutique SRL', 'CLIENT');
   COMMIT;
   ```
3. Revino în aplicație, scrie `DOC-LOCAL-1` în bara de căutare → apare instantaneu!

### 3.2 — Fragment Vertical: LMD local → vizibil în V_ITEMS
1. Deschide tab-ul **Local: Catalog** și observă un produs din `ITEMS_CORE` (notează-i ID-ul).
2. Deschide tab-ul **Global: Produse** — vezi că produsul e prezent (prin V_ITEMS = JOIN).
3. Dacă ar fi modificat direct `ITEMS_CORE` (cod/nume), schimbarea s-ar reflecta automat în V_ITEMS.

### 3.3 — Relații Replicate: LMD local → vizibil după MV Refresh
1. Deschide tab-ul **Replicare MV**.
2. Observă cele 2 tabele: Master (DISTRIBUȚIE) vs Replica (MV_CLIENTI din VÂNZĂRI).
3. Adaugă un client nou în tab-ul **Local: Distribuție** (ex. `CLI-MV-TEST`).
4. Revino la **Replicare MV** — master-ul are clientul nou, dar replica încă nu.
5. Apasă butonul **🔄 Refresh Materialized Views**.
6. Replica se sincronizează — clientul nou apare acum și în `MV_CLIENTI`!

---

## 📍 Cerința 4: Propagare operații LMD globale la nivele locale (3p)
**Obiectiv:** Demonstrarea inteligenței sistemului de a primi un rând nou în view-ul global și a-l sparge/trimite corect către tabelele/PDB-urile locale, pe baza regulilor de fragmentare (folosind triggerele `INSTEAD OF`).

### 4.1 — Propagare prin V_FISE_CLIENTI (fragmentare orizontală)
1. Rămâi pe tab-ul **Global: Facturi**.
2. Adaugă o factură cu Moneda **RON** (ex: `FACT-RO-01`, Valoare: `100`). Apasă **Salvează**.
3. Adaugă o factură cu Moneda **USD** (ex: `FACT-EXT-01`, Valoare: `500`). Apasă **Salvează**.
4. Scrie `FACT-` în bara de căutare — ambele facturi sunt vizibile la nivel global.
5. **Verificare propagare:**
   - Deschide tab-ul **Local: Vânzări RO**, caută `FACT-RO-01` → e aici (moneda RON → fragment RO).
   - Deschide tab-ul **Local: Vânzări EXT**, caută `FACT-EXT-01` → e aici (moneda USD → fragment EXT).
6. Alternativ, verifică în SQL Developer:
   ```sql
   SELECT * FROM fise_clienti_ro WHERE nr_document = 'FACT-RO-01';   -- Rutată automat în RO
   SELECT * FROM fise_clienti_ext WHERE nr_document = 'FACT-EXT-01'; -- Rutată automat în EXT
   ```

### 4.2 — Propagare prin V_ITEMS (fragmentare verticală)
1. Deschide tab-ul **Global: Produse**.
2. Adaugă un produs nou: Cod `PROD-TEST-01`, Nume `Pantof Test`, Descriere `Test vertical`, Activ.
3. Apasă **Salvează** → trigger-ul `INSTEAD OF INSERT` pe V_ITEMS împarte automat datele.
4. **Verificare:** Deschide tab-ul **Local: Catalog** și verifică:
   - `ITEMS_CORE` conține `PROD-TEST-01` (cod + nume)
   - `ITEMS_EXTRA` conține (descriere + TVA) pentru același ID
5. Ai demonstrat că un singur INSERT la nivel global a fost **despărțit automat** în 2 tabele fizice!
