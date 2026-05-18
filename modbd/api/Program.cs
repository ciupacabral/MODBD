using Microsoft.EntityFrameworkCore;
using ModbdApi.Models;
using ModbdApi.Data;
using ModbdApi.DTOs;
using Oracle.ManagedDataAccess.Client;
using System.Text;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowAll", builder =>
    {
        builder.AllowAnyOrigin().AllowAnyMethod().AllowAnyHeader();
    });
});

// Configurarea bazelor de data PDB (Distributie, Catalog, Vanzari)
builder.Services.AddDbContext<DistributieDbContext>(options =>
    options.UseOracle(builder.Configuration.GetConnectionString("DistributieDB")));
    
builder.Services.AddDbContext<CatalogDbContext>(options =>
    options.UseOracle(builder.Configuration.GetConnectionString("CatalogDB")));
    
builder.Services.AddDbContext<VanzariDbContext>(options =>
    options.UseOracle(builder.Configuration.GetConnectionString("VanzariDB")));

var app = builder.Build();
app.UseCors("AllowAll");

// Cerinta 1: Preluare date de la nivelul bazei de date locale (PDB Distribuție)
// Acest endpoint extrage toți clienții direct din tabelul local clienti.
app.MapGet("/api/distributie/clienti", async (int? page, int? pageSize, string? search, DistributieDbContext db) =>
{
    // vom folosi paginarea pentru a nu incarca UI-ul cu atat de mult date
    int p = page ?? 1;
    int ps = pageSize ?? 20;
    var query = db.Clienti.AsQueryable();
    
    if (!string.IsNullOrEmpty(search))
    {
        query = query
            .Where(c => c.CodClient
                .ToLower()
                .Contains(search.ToLower()));
    }
    
    query = query
        .OrderByDescending(c => c.Id);
    
    var total = await query
        .CountAsync();
    
    var data = await query
        .Skip((p - 1) * ps)
        .Take(ps)
        .ToListAsync();
    
    return Results.Ok(new { 
        data, 
        total, 
        page = p, 
        pageSize = ps, 
        totalPages = (int)Math.Ceiling((double)total / ps) 
    });
});

// Preluare zone disponibile
app.MapGet("/api/distributie/zone", async (DistributieDbContext db) =>
{
    var zone = await db.Zone
        .OrderBy(z => z.Id)
        .ToListAsync();
    
    return Results.Ok(zone);
});

// Cerinta 1: Introducere si gestionare informatii la nivelul bazei de date locale
// Acest endpoint insereaza un client nou direct în tabelul din PDB Distribuție.
app.MapPost("/api/distributie/clienti", async (ClientInput input, DistributieDbContext db) =>
{
    long nextId = (await db.Clienti
        .MaxAsync(c => (long?)c.Id) ?? 0) + 1;
    
    var client = new Client
    {
        Id = nextId,
        CodClient = input.CodClient,
        DenumireClient = input.DenumireClient,
        TipClient = input.TipClient,
        IdZona = input.IdZona,
        StartDate = DateTime.Now,
        EndDate = input.EndDate
    };

    db.Clienti.Add(client);
    await db.SaveChangesAsync();

    return Results.Created("/api/distributie/clienti", client);
});

// Cerinta 1: Actualizare client existent la nivelul bazei de date locale
app.MapPut("/api/distributie/clienti/{id}", async (long id, ClientInput input, DistributieDbContext db) =>
{
    var client = await db.Clienti.FindAsync(id);
    if (client is null) return Results.NotFound();
    client.CodClient = input.CodClient;
    client.DenumireClient = input.DenumireClient;
    client.TipClient = input.TipClient;
    client.IdZona = input.IdZona;
    client.EndDate = input.EndDate;
    await db.SaveChangesAsync();
    return Results.Ok(client);
});

// Cerinta 1: Stergere client din baza de date locala
app.MapDelete("/api/distributie/clienti/{id}", async (long id, DistributieDbContext db, VanzariDbContext vanzariDb) =>
{
    var client = await db.Clienti.FindAsync(id);
    if (client is null) return Results.NotFound();
    try
    {
        // 1. Găsim numerele de document pentru facturile clientului (din VANZARI)
        var fiseRoNrs = await vanzariDb.FiseRo.Where(f => f.CodClient == client.CodClient).Select(f => f.NrDocument).ToListAsync();
        var fiseExtNrs = await vanzariDb.FiseExt.Where(f => f.CodClient == client.CodClient).Select(f => f.NrDocument).ToListAsync();
        var allDocNrs = fiseRoNrs.Concat(fiseExtNrs).ToList();

        // 2. Ștergem liniile de factură asociate (prin EF Core, pe view-ul global V_LINII_DOC)
        if (allDocNrs.Any())
        {
            await vanzariDb.Linii.Where(l => allDocNrs.Contains(l.NrDocument)).ExecuteDeleteAsync();
        }

        // 3. Ștergem facturile (prin EF Core)
        await vanzariDb.FiseRo.Where(f => f.CodClient == client.CodClient).ExecuteDeleteAsync();
        await vanzariDb.FiseExt.Where(f => f.CodClient == client.CodClient).ExecuteDeleteAsync();

        // 4. Ștergem contactele (DISTRIBUTIE)
        await db.Contacte.Where(c => c.CodClient == client.CodClient).ExecuteDeleteAsync();
        
        // 5. Ștergem clientul (DISTRIBUTIE)
        db.Clienti.Remove(client);
        await db.SaveChangesAsync();
        
        return Results.NoContent();
    }
    catch (Exception ex)
    {
        return Results.Json(new { error = "Nu se poate șterge clientul. Eroare: " + (ex.InnerException?.Message ?? ex.Message) }, statusCode: 400);
    }
});

// Cerintele 2 si 3: Vizualizare date la nivelul bazei de date globale (Produse)
// Extrage datele din view-ul V_ITEMS care combina fragmentul CORE cu cel EXTRA.
app.MapGet("/api/global/items", async (int? page, int? pageSize, CatalogDbContext db) =>
{
    int p = page ?? 1;
    int ps = pageSize ?? 20;
    
    var query = db.Items
        .OrderByDescending(i => i.Id);
    
    var total = await query
        .CountAsync();
    
    var data = await query
        .Skip((p - 1) * ps)
        .Take(ps)
        .ToListAsync();
    
    return Results.Ok(new { 
        data, 
        total, 
        page = p, 
        pageSize = ps, 
        totalPages = (int)Math.Ceiling((double)total / ps) 
    });
});

// Cerinta 4: Propagare operatii LMD globale la nivele locale (Produse)
// Inserția se face în view-ul global V_ITEMS, iar Oracle (cu ajutorul trigger-ului INSTEAD OF) sparge 
// și ruteaza automat datele catre tabelele items_core si items_extra.
app.MapPost("/api/global/items", async (ItemInput input, CatalogDbContext db) =>
{
    long nextId = (await db.Items
        .MaxAsync(i => (long?)i.Id) ?? 0) + 1;
    
    var item = new GlobalItem
    {
        Id = nextId,
        ItemCode = input.ItemCode,
        ItemName = input.ItemName,
        Description = input.Description,
        Active = input.Active
    };
    
    db.Items.Add(item);
    await db.SaveChangesAsync();
    
    return Results.Created("/api/global/items", item);
});

// Cerintele 2 si 3: Vizualizare date la nivelul bazei de date globale (Facturi)
// Extrage datele din view-ul V_FISE_CLIENTI care face un UNION ALL peste fise_ro și fise_ext.
app.MapGet("/api/global/fise", async (int? page, int? pageSize, string? search, VanzariDbContext db) =>
{
    int p = page ?? 1;
    int ps = pageSize ?? 20;
    var query = db.Fise.AsQueryable();
    
    if (!string.IsNullOrEmpty(search))
    {
        query = query
            .Where(f => f.NrDocument
                .ToLower()
                .Contains(search.ToLower()));
    }
    
    query = query
        .OrderByDescending(f => f.Id);
    
    var total = await query
        .CountAsync();
    
    var data = await query
        .Skip((p - 1) * ps)
        .Take(ps)
        .ToListAsync();
        
    return Results.Ok(new { 
        data, 
        total, 
        page = p, 
        pageSize = ps, 
        totalPages = (int)Math.Ceiling((double)total / ps) 
    });
});

// Cerinta 4: Propagare operatii LMD globale la nivele locale (Facturi)
// Inserarea se face la nivel global în V_FISE_CLIENTI. Triggerul INSTEAD OF analizeaza 'Moneda' 
// și dupa aceea, in functie de valoarea monedei (RON sau ceva diferit de RON),
// directioneaza randul catre fragmentul corespunzator (RO sau EXT).
app.MapPost("/api/global/fise", async (FisaInput input, VanzariDbContext db) =>
{
    long nextId = (await db.Fise
        .MaxAsync(f => (long?)f.Id) ?? 0) + 1;
    
    var fisa = new GlobalFisa
    {
        Id = nextId,
        NrDocument = input.NrDocument,
        NrDocInitial = input.NrDocInitial,
        DocType = input.DocType,
        Moneda = input.Moneda,
        Amount = input.Amount,
        AmountRon = input.Amount,
        CodClient = input.CodClient ?? "CLI000001",
        DataDocEfectiva = DateTime.Now,
        DataScad = input.DataScad,
        PlataPrin = input.PlataPrin
    };

    db.Fise.Add(fisa);
    await db.SaveChangesAsync();

    return Results.Created("/api/global/fise", fisa);
});

// =====================================================================
// P2: CRUD Local CATALOG — Fragmente verticale (items_core + items_extra)
// =====================================================================

// Cerinta 1: Vizualizare fragment vertical ITEMS_CORE (identitate + clasificare)
app.MapGet("/api/catalog/items-core", async (int? page, int? pageSize, CatalogDbContext db) =>
{
    int p = page ?? 1;
    int ps = pageSize ?? 15;
    var query = db.ItemsCore.OrderByDescending(i => i.Id);
    var total = await query.CountAsync();
    var data = await query.Skip((p - 1) * ps).Take(ps).ToListAsync();
    return Results.Ok(new { data, total, page = p, pageSize = ps, totalPages = (int)Math.Ceiling((double)total / ps) });
});

// Cerinta 1: Vizualizare fragment vertical ITEMS_EXTRA (atribute comerciale + fizice)
app.MapGet("/api/catalog/items-extra", async (int? page, int? pageSize, CatalogDbContext db) =>
{
    int p = page ?? 1;
    int ps = pageSize ?? 15;
    var query = db.ItemsExtra.OrderByDescending(i => i.Id);
    var total = await query.CountAsync();
    var data = await query.Skip((p - 1) * ps).Take(ps).ToListAsync();
    return Results.Ok(new { data, total, page = p, pageSize = ps, totalPages = (int)Math.Ceiling((double)total / ps) });
});

// Cerinta 1 + 3: Update direct pe fragmentul vertical ITEMS_CORE
// Modificarea se va reflecta automat in view-ul global V_ITEMS (transparenta)
app.MapPut("/api/catalog/items-core/{id}", async (long id, ItemCore input, CatalogDbContext db) =>
{
    var item = await db.ItemsCore.FindAsync(id);
    if (item is null) return Results.NotFound();
    item.ItemCode = input.ItemCode;
    item.ItemName = input.ItemName;
    item.Active = input.Active;
    await db.SaveChangesAsync();
    return Results.Ok(item);
});

// Cerinta 1: Stergere directa din ITEMS_CORE (CASCADE sterge si ITEMS_EXTRA)
app.MapDelete("/api/catalog/items-core/{id}", async (long id, CatalogDbContext db, VanzariDbContext vanzariDb) =>
{
    var item = await db.ItemsCore.FindAsync(id);
    if (item is null) return Results.NotFound();
    
    try
    {
        // 1. Ștergem liniile de factură care folosesc acest produs (din PDB VANZARI)
        // Folosind EF Core pe V_LINII_DOC, declanșăm INSTEAD OF DELETE care curăță din linii_doc_ro/ext
        await vanzariDb.Linii.Where(l => l.ItemCode == item.ItemCode).ExecuteDeleteAsync();

        // 2. Ștergem produsul (din PDB CATALOG)
        // ITEMS_EXTRA e șters automat prin FK cu ON DELETE CASCADE de la nivelul BD
        db.ItemsCore.Remove(item);
        await db.SaveChangesAsync();
        
        return Results.NoContent();
    }
    catch (Exception ex)
    {
        return Results.Json(new { error = "Nu se poate șterge produsul. Eroare: " + (ex.InnerException?.Message ?? ex.Message) }, statusCode: 400);
    }
});

// =====================================================================
// P3: CRUD Local VANZARI — Fragmente orizontale (fise_ro + fise_ext)
// =====================================================================

// Cerinta 1 + 3: Vizualizare fragment orizontal FISE_CLIENTI_RO (moneda = RON)
app.MapGet("/api/vanzari/fise-ro", async (int? page, int? pageSize, string? search, VanzariDbContext db) =>
{
    int p = page ?? 1;
    int ps = pageSize ?? 15;
    var query = db.FiseRo.AsQueryable();
    if (!string.IsNullOrEmpty(search))
        query = query.Where(f => f.NrDocument.ToLower().Contains(search.ToLower()));
    query = query.OrderByDescending(f => f.Id);
    var total = await query.CountAsync();
    var data = await query.Skip((p - 1) * ps).Take(ps)
        .ToListAsync();
    return Results.Ok(new { data, total, page = p, pageSize = ps, totalPages = (int)Math.Ceiling((double)total / ps) });
});

// Cerinta 1 + 3: Vizualizare fragment orizontal FISE_CLIENTI_EXT (moneda <> RON)
app.MapGet("/api/vanzari/fise-ext", async (int? page, int? pageSize, string? search, VanzariDbContext db) =>
{
    int p = page ?? 1;
    int ps = pageSize ?? 15;
    var query = db.FiseExt.AsQueryable();
    if (!string.IsNullOrEmpty(search))
        query = query.Where(f => f.NrDocument.ToLower().Contains(search.ToLower()));
    query = query.OrderByDescending(f => f.Id);
    var total = await query.CountAsync();
    var data = await query.Skip((p - 1) * ps).Take(ps)
        .ToListAsync();
    return Results.Ok(new { data, total, page = p, pageSize = ps, totalPages = (int)Math.Ceiling((double)total / ps) });
});

// =====================================================================
// P4: Vizualizare V_LINII_DOC (completare Cerinta 2)
// =====================================================================

// Cerinta 2: Vizualizare globala a liniilor de document (UNION ALL linii_doc_ro + linii_doc_ext)
app.MapGet("/api/global/linii", async (int? page, int? pageSize, VanzariDbContext db) =>
{
    int p = page ?? 1;
    int ps = pageSize ?? 15;
    var query = db.Linii.OrderByDescending(l => l.Id);
    var total = await query.CountAsync();
    var data = await query.Skip((p - 1) * ps).Take(ps).ToListAsync();
    return Results.Ok(new { data, total, page = p, pageSize = ps, totalPages = (int)Math.Ceiling((double)total / ps) });
});

// =====================================================================
// P5: MV-uri replicate + Refresh (Cerinta 2 + 3 relatii replicate)
// =====================================================================

// Vizualizare MV_CLIENTI (replica DISTRIBUTIE.clienti in VANZARI)
app.MapGet("/api/vanzari/mv-clienti", async (int? page, int? pageSize, VanzariDbContext db) =>
{
    int p = page ?? 1;
    int ps = pageSize ?? 15;
    var query = db.MvClienti.OrderByDescending(c => c.Id);
    var total = await query.CountAsync();
    var data = await query.Skip((p - 1) * ps).Take(ps).ToListAsync();
    return Results.Ok(new { data, total, page = p, pageSize = ps, totalPages = (int)Math.Ceiling((double)total / ps) });
});

// Vizualizare MV_ITEMS_CORE (replica CATALOG.items_core in VANZARI)
app.MapGet("/api/vanzari/mv-items-core", async (int? page, int? pageSize, VanzariDbContext db) =>
{
    int p = page ?? 1;
    int ps = pageSize ?? 15;
    var query = db.MvItemsCore.OrderByDescending(c => c.Id);
    var total = await query.CountAsync();
    var data = await query.Skip((p - 1) * ps).Take(ps).ToListAsync();
    return Results.Ok(new { data, total, page = p, pageSize = ps, totalPages = (int)Math.Ceiling((double)total / ps) });
});

// Refresh manual al Materialized Views din VANZARI
// Refreshuim MV_CLIENTI, MV_ZONE și MV_ITEMS_CORE.
// Atenție: Dacă se șterge un item care are linii de factură asociate, 
// refresh-ul MV_ITEMS_CORE ar putea eșua din cauza FK_LIN_EXT_ITEM.
app.MapPost("/api/admin/refresh-mv", async (VanzariDbContext db) =>
{
    // Pas 1: FAST refresh prin job-ul existent
    try
    {
        await db.Database.ExecuteSqlRawAsync(@"
            BEGIN
                DBMS_SCHEDULER.RUN_JOB('JOB_REFRESH_MVS', use_current_session => TRUE);
            END;");
        return Results.Ok(new { message = "MV-urile au fost actualizate cu succes (FAST refresh)." });
    }
    catch (Exception fastEx)
    {
        // ORA-02292: o stergere in master este blocata de un FK din VANZARI catre MV
        // (ex: ai sters un client/produs care are facturi/linii); userul trebuie sa
        // stearga manual datele dependente inainte de a putea propaga stergerea.
        if (fastEx.Message.Contains("ORA-02292"))
        {
            return Results.Json(new
            {
                error = "Nu se poate sincroniza: Clientul sau Produsul pe care l-ai șters are facturi/linii asociate în PDB VÂNZĂRI. Șterge mai întâi datele dependente."
            }, statusCode: 400);
        }

        // ORA-12034 (MV log mai recent decat ultimul refresh) sau alta eroare la
        // FAST refresh: facem recovery automat printr-un COMPLETE non-atomic.
        // Strategia: dezactivam temporar FK-urile catre MV-uri (TRUNCATE-ul de la
        // refresh nu poate rula cu FK enabled), facem refresh, reactivam FK-urile
        // cu VALIDATE. Daca dupa refresh exista facturi orfane (cod_client sau
        // item_code lipsa din master), ENABLE VALIDATE va ridica ORA-02298 si vom
        // raporta exact ce a esuat.
        var isMvLogStale = fastEx.Message.Contains("ORA-12034")
                          || fastEx.Message.Contains("ORA-30439")
                          || fastEx.Message.Contains("ORA-12048");
        if (!isMvLogStale)
        {
            return Results.Json(new { error = "Eroare la refresh: " + fastEx.Message }, statusCode: 500);
        }

        try
        {
            await db.Database.ExecuteSqlRawAsync(@"
                BEGIN
                    EXECUTE IMMEDIATE 'ALTER TABLE fise_clienti_ro  DISABLE CONSTRAINT fk_fise_ro_client';
                    EXECUTE IMMEDIATE 'ALTER TABLE fise_clienti_ext DISABLE CONSTRAINT fk_fise_ext_client';
                    EXECUTE IMMEDIATE 'ALTER TABLE linii_doc_ro     DISABLE CONSTRAINT fk_lin_ro_item';
                    EXECUTE IMMEDIATE 'ALTER TABLE linii_doc_ext    DISABLE CONSTRAINT fk_lin_ext_item';

                    DBMS_MVIEW.REFRESH(
                        LIST           => 'MV_CLIENTI,MV_ZONE,MV_ITEMS_CORE,MV_BRANDS,MV_ITEMS_CATEGORY,MV_ITEMS_TYPE,MV_ITEMS_SEASONS',
                        METHOD         => 'CCCCCCC',
                        ATOMIC_REFRESH => FALSE
                    );

                    EXECUTE IMMEDIATE 'ALTER TABLE fise_clienti_ro  ENABLE VALIDATE CONSTRAINT fk_fise_ro_client';
                    EXECUTE IMMEDIATE 'ALTER TABLE fise_clienti_ext ENABLE VALIDATE CONSTRAINT fk_fise_ext_client';
                    EXECUTE IMMEDIATE 'ALTER TABLE linii_doc_ro     ENABLE VALIDATE CONSTRAINT fk_lin_ro_item';
                    EXECUTE IMMEDIATE 'ALTER TABLE linii_doc_ext    ENABLE VALIDATE CONSTRAINT fk_lin_ext_item';
                END;");

            return Results.Ok(new
            {
                message = "MV-urile au fost actualizate cu succes (auto-recovery: COMPLETE refresh, FK-urile au fost re-validate)."
            });
        }
        catch (Exception recoveryEx)
        {
            // Daca ENABLE VALIDATE pica (ORA-02298), avem facturi orfane in VANZARI;
            // raportam ce am gasit. FK-urile au ramas DISABLED — userul trebuie
            // sa curete datele si sa cheme din nou refresh-ul.
            return Results.Json(new
            {
                error = "Recovery COMPLETE refresh a eșuat: " + recoveryEx.Message
                      + " — atenție: FK-urile MV pot fi rămase DISABLED. Verifică facturi/linii orfane în FISE_CLIENTI_RO/EXT și LINII_DOC_RO/EXT."
            }, statusCode: 500);
        }
    }
});

// =====================================================================
// Cerinta 4: INSERT ATOMIC document + linii prin view-urile de transparenta
// =====================================================================
// Aplicatia primeste {header, [linii...]} intr-un singur request.
// Backend deschide o tranzactie si executa:
//   1. INSERT prin V_FISE_CLIENTI -> trigger INSTEAD OF ruteaza header-ul
//      spre fragmentul fizic RO sau EXT pe baza monedei (transparenta H).
//   2. INSERT ALL pe V_LINII_DOC intr-un singur statement -> trigger-ul
//      agregat de coerenta vede toate liniile odata, verifica sum_doc =
//      sum_linii, si nu ridica fals-pozitiv.
// Daca suma liniilor nu coincide cu amount_doc, tranzactia se rollback
// (ORA-20001 ridicat de trigger-ul compound trg_coerenta_sum_*).
// =====================================================================
app.MapPost("/api/global/documents", async (DocumentWithLinesInput input, VanzariDbContext db) =>
{
    using var tx = await db.Database.BeginTransactionAsync();
    try
    {
        // (1) Calculam ID-uri urmatoare (FK + UK enforcement)
        long headerId = (await db.Fise.MaxAsync(f => (long?)f.Id) ?? 0) + 1;
        long lineIdStart = (await db.Database
            .SqlQueryRaw<long>("SELECT NVL(MAX(id), 0) AS Value FROM v_linii_doc")
            .FirstAsync()) + 1;

        // (2) INSERT header prin view-ul de transparenta orizontala.
        //     Trigger INSTEAD OF INSERT pe V_FISE_CLIENTI ruteaza dupa moneda.
        //     Folosim toate cele 15 coloane din V_FISE_CLIENTI; ce nu primim din
        //     UI ramane NULL (sau default rezonabil pentru cele NOT NULL).
        var nrDocInitialParam = (object?)input.NrDocInitial ?? DBNull.Value;
        var dataScadParam     = (object?)input.DataScad     ?? DBNull.Value;
        var plataPrinParam    = (object?)input.PlataPrin    ?? DBNull.Value;

        await db.Database.ExecuteSqlInterpolatedAsync($@"
            INSERT INTO v_fise_clienti (
                id, nr_document, nr_doc_initial, tip_doc, doc_type_xrp,
                data_doc_efectiva, data_scad, semn, moneda,
                amount_doc, amount_doc_ron, plata_prin,
                cod_client, denumire_client, clasa_client
            ) VALUES (
                {headerId}, {input.NrDocument}, {nrDocInitialParam}, 'F', {input.DocType},
                SYSDATE, {dataScadParam}, 1, {input.Moneda},
                {input.Amount}, {input.Amount}, {plataPrinParam},
                {input.CodClient ?? "CLI000001"},
                {input.DenumireClient ?? "Client UI"},
                {input.ClasaClient ?? "CLASA_A"}
            )");

        // (3) INSERT ALL liniile intr-un singur statement (atomic).
        //     Folosim parametri pozitionati (siguranta SQL injection).
        //     Mapam toate cele 13 coloane din V_LINII_DOC; daca UI-ul nu trimite
        //     valorile XRP_LINIE_*, le derivam din XRP_DOC_* (caz uzual).
        if (input.Linii.Count > 0)
        {
            var sb = new StringBuilder("INSERT ALL\n");
            var parameters = new List<OracleParameter>();
            int pIdx = 0;
            int lineOffset = 0;

            foreach (var linie in input.Linii)
            {
                int idP        = pIdx++;
                int docP       = pIdx++;
                int nrP        = pIdx++;
                int itemP      = pIdx++;
                int qtyP       = pIdx++;
                int docValP    = pIdx++;
                int docTvaP    = pIdx++;
                int docPctP    = pIdx++;
                int docTotP    = pIdx++;
                int linWvatP   = pIdx++;
                int linValP    = pIdx++;
                int linTvaP    = pIdx++;
                int linPctP    = pIdx++;

                sb.AppendLine($@"  INTO v_linii_doc (
                    id, doc_type_xrp, nr_document, item_code, item_qty,
                    xrp_doc_valoare_fara_tva, xrp_doc_tva, xrp_doc_procent_tva, xrp_doc_valoare_totala,
                    xrp_linie_is_with_vat, xrp_linie_valoare_fara_tva, xrp_linie_tva, xrp_linie_proc_tva
                ) VALUES (
                    :p{idP}, :p{docP}, :p{nrP}, :p{itemP}, :p{qtyP},
                    :p{docValP}, :p{docTvaP}, :p{docPctP}, :p{docTotP},
                    :p{linWvatP}, :p{linValP}, :p{linTvaP}, :p{linPctP}
                )");

                // Calcule derivate cand UI-ul nu trimite valorile detaliate.
                decimal procentTva = linie.ProcentTva ?? (
                    linie.ValoareFaraTva > 0 ? Math.Round(linie.Tva / linie.ValoareFaraTva * 100, 2) : 0
                );
                decimal valoareTotala = linie.ValoareFaraTva + linie.Tva;
                decimal linieValoareFaraTva = linie.LinieValoareFaraTva ?? linie.ValoareFaraTva;
                decimal linieTva = linie.LinieTva ?? linie.Tva;
                decimal linieProcTva = linie.LinieProcTva ?? procentTva;
                string  linieIsWithVat = linie.LinieIsWithVat ?? (linie.Tva > 0 ? "Y" : "N");

                parameters.Add(new OracleParameter($"p{idP}",      lineIdStart + lineOffset));
                parameters.Add(new OracleParameter($"p{docP}",     input.DocType));
                parameters.Add(new OracleParameter($"p{nrP}",      input.NrDocument));
                parameters.Add(new OracleParameter($"p{itemP}",    linie.ItemCode));
                parameters.Add(new OracleParameter($"p{qtyP}",     linie.ItemQty));
                parameters.Add(new OracleParameter($"p{docValP}",  linie.ValoareFaraTva));
                parameters.Add(new OracleParameter($"p{docTvaP}",  linie.Tva));
                parameters.Add(new OracleParameter($"p{docPctP}",  procentTva));
                parameters.Add(new OracleParameter($"p{docTotP}",  valoareTotala));
                parameters.Add(new OracleParameter($"p{linWvatP}", linieIsWithVat));
                parameters.Add(new OracleParameter($"p{linValP}",  linieValoareFaraTva));
                parameters.Add(new OracleParameter($"p{linTvaP}",  linieTva));
                parameters.Add(new OracleParameter($"p{linPctP}",  linieProcTva));

                lineOffset++;
            }

            sb.AppendLine("SELECT * FROM dual");

            // Trigger-ul compound trg_coerenta_sum_ro / _ext fires aici, AFTER STATEMENT.
            // Vede toate liniile inserate + verifica sum_doc = sum_linii.
            await db.Database.ExecuteSqlRawAsync(sb.ToString(), parameters.ToArray());
        }

        await tx.CommitAsync();

        return Results.Created($"/api/global/documents/{headerId}", new
        {
            id = headerId,
            nrDocument = input.NrDocument,
            moneda = input.Moneda,
            amount = input.Amount,
            nrLinii = input.Linii.Count,
            message = $"Document {input.NrDocument} salvat cu {input.Linii.Count} linii. " +
                      $"Ruta automat in fragment {(input.Moneda == "RON" ? "RO" : "EXT")}."
        });
    }
    catch (Exception ex)
    {
        await tx.RollbackAsync();

        // Erori asteptate frecvent:
        // - ORA-20001: trigger agregat (sum_doc != sum_linii)
        // - ORA-02291: FK violation (cod_client sau item_code inexistent)
        // - ORA-00001: unique violation (nr_document + doc_type_xrp deja existent)
        string msg = ex.Message;
        if (msg.Contains("ORA-20001"))
            msg = "Suma liniilor nu coincide cu Amount-ul documentului. Verifica calculul.";
        else if (msg.Contains("ORA-02291"))
            msg = "Client sau produs inexistent. Verifica codurile.";
        else if (msg.Contains("ORA-00001"))
            msg = "Document cu acest nr_document + doc_type_xrp exista deja.";

        return Results.BadRequest(new { error = msg, oracle_full = ex.Message });
    }
});


app.Run("http://localhost:5050");