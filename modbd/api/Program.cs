using Microsoft.EntityFrameworkCore;
using ModbdApi.Models;
using ModbdApi.Data;
using ModbdApi.DTOs;

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
        StartDate = DateTime.Now
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
        DocType = input.DocType,
        Moneda = input.Moneda,
        Amount = input.Amount,
        AmountRon = input.Amount,
        CodClient = input.CodClient ?? "CLI000001",
        DataDocEfectiva = DateTime.Now
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
    try
    {
        await db.Database.ExecuteSqlRawAsync(@"
            BEGIN
                DBMS_SCHEDULER.RUN_JOB('JOB_REFRESH_MVS', use_current_session => TRUE);
            END;");
        return Results.Ok(new { message = "MV-urile au fost actualizate cu succes!" });
    }
    catch (Exception ex)
    {
        if (ex.Message.Contains("ORA-02292"))
        {
            return Results.Json(new { error = "Nu se poate sincroniza: Clientul sau Produsul pe care l-ai șters are facturi asociate în PDB VÂNZĂRI. Șterge facturile mai întâi!" }, statusCode: 400);
        }
        return Results.Ok(new { message = "Eroare la refresh: " + ex.Message });
    }
});

app.Run("http://localhost:5050");