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
        .Select(f => new { f.Id, NrDocument = f.NrDocument, DocType = f.DocType,
            Moneda = f.Moneda, Amount = f.Amount, Client = f.CodClient })
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

app.Run("http://localhost:5050");