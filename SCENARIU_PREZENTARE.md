# Scenariu de Prezentare - Modulul Front-End (MODBD)

Acest document este un ghid pas cu pas pe care îl poți folosi în timpul prezentării proiectului pentru a demonstra că aplicația ta acoperă toate cele 4 cerințe (10 puncte) de la implementarea Front-End.

Înainte de a începe, asigură-te că:
1. Ai pornit baza de date Oracle în Docker (`docker start oracle-modbd`).
2. Ai pornit API-ul din terminal cu `dotnet run` (în folderul `modbd/api`).
3. Ai deschis interfața web `index.html` în browser.

---

## 📍 Cerința 1: Management la nivelul bazelor de date locale (3p)
**Obiectiv:** Demonstrarea capacității de a face operații (CRUD) direct pe un nod local (PDB-ul `DISTRIBUTIE`), fără a trece prin view-uri globale de fragmentare.

**Pași de urmat:**
1. Deschide aplicația web pe secțiunea (tab-ul) **Local: Distribuție**.
2. Arată profesorului tabelul deja populat cu date extrase din baza locală.
3. Folosește formularul **Adaugă Client** din dreapta pentru a introduce o înregistrare nouă:
   - Cod: `CLI999`
   - Nume: `Client Test Local`
   - Tip: `CLIENT`
   - Zonă: Alege orice zonă din dropdown (ex. `MOLDOVA` sau `BUCURESTI`)
4. Apasă butonul **Salvează**.
5. Pentru o demonstrație rapidă, scrie `CLI999` în noua **bară de căutare inteligentă** de deasupra tabelului.
6. Arată-i profesorului cum tabelul s-a filtrat, lăsând vizibil noul client abia introdus. Ai demonstrat că ai introdus și gestionat date local!

---

## 📍 Cerința 2: Vizualizare la nivelul bazei de date globale (1p)
**Obiectiv:** Demonstrarea capacității aplicației de a afișa date unificate, obținute din combinarea mai multor baze de date locale (Transparență).

**Pași de urmat:**
1. Mergi la secțiunea **Vizualizare Globală - Facturi**.
2. Explică profesorului că acest tabel interoghează view-ul global `V_FISE_CLIENTI` (stabilit prin codul .NET `await db.Fise.ToListAsync()`).
3. Menționează că acest view face un `UNION ALL` între fragmentul local `RO` și fragmentul extern `EXT`, oferind utilizatorului o viziune completă și unificată, printr-un singur apel către API.

---

## 📍 Cerința 3: Vizualizare la nivel global a operațiilor LMD locale (2p)
**Obiectiv:** Demonstrarea faptului că, dacă cineva modifică date direct într-un fragment local, modificarea se reflectă instantaneu la nivel global, fără sincronizări adiționale.

**Pași de urmat:**
1. Lasă aplicația web deschisă pe secțiunea **Vizualizare Globală - Facturi**.
2. Deschide terminalul, SQL Developer sau DBeaver și conectează-te pe nodul de vânzări (`PDB_VANZARI`).
3. Rulează o comandă LMD manuală direct pe tabelul fizic local de facturi (ex. facturi în RON):
   ```sql
   INSERT INTO fise_clienti_ro (id, nr_document, tip_doc, doc_type_xrp, data_doc_efectiva, semn,
                                moneda, amount_doc, amount_doc_ron, cod_client, denumire_client, clasa_client)
   VALUES (9999, 'DOC-LOCAL-1', 'F', 'INV', SYSDATE, 1,
           'RON', 500, 500, 'CLI000009', 'Iota Boutique SRL', 'CLIENT');
   COMMIT;
   ```
4. Revino în aplicația web și apasă butonul **Reîncarcă Tabel**.
5. Pentru o demonstrație rapidă și de efect, scrie `DOC-LOCAL-1` în noua **bară de căutare inteligentă** de deasupra tabelului.
6. Arată profesorului cum lista se filtrează instantaneu, lăsând vizibil doar documentul tocmai introdus pe nodul local. Ai demonstrat vizualizarea globală a unui LMD efectuat la nivel local!

---

## 📍 Cerința 4: Propagare operații LMD globale la nivele locale (3p)
**Obiectiv:** Demonstrarea inteligenței sistemului de a primi un rând nou în view-ul global și a-l sparge/trimite corect către tabelele/PDB-urile locale, pe baza regulilor de fragmentare (folosind triggerele `INSTEAD OF`).

**Pași de urmat:**
1. Rămâi pe secțiunea **Vizualizare Globală - Facturi**.
2. Folosește formularul din interfață pentru a adăuga o factură cu Moneda **RON** (ex: `FACT-RO-01`, Valoare: `100`).
3. Folosește formularul din nou pentru a adăuga o factură cu Moneda **USD** (ex: `FACT-EXT-01`, Valoare: `500`).
4. (Bonus vizual) Scrie `FACT-` în bara de căutare din interfață pentru a-i arăta profesorului că ambele facturi sunt vizibile și au fost salvate la nivel global.
5. **Demonstrația propagării:** Deschide SQL Developer pe baza de date `PDB_VANZARI` și rulează aceste scripturi pentru a verifica tabelele fizice:
   ```sql
   SELECT * FROM fise_clienti_ro WHERE nr_document = 'FACT-RO-01';  
   -- Rezultat: Factura a fost rutată automat aici datorită monedei RON.

   SELECT * FROM fise_clienti_ext WHERE nr_document = 'FACT-EXT-01'; 
   -- Rezultat: Factura a fost rutată automat aici deoarece moneda (USD) e diferită de RON.
   ```
5. Explică profesorului: "Aplicația front-end a trimis un request orb către baza globală (`INSERT INTO V_FISE_CLIENTI`), iar baza de date Oracle, prin triggerul INSTEAD OF setat, a analizat moneda și a direcționat rândul către fragmentul fizic corespunzător. Astfel, front-end-ul rămâne decuplat de complexitatea bazelor de date distribuite."
