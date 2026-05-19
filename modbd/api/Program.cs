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

// Configurare DbContext pentru cele trei PDB-uri (Distributie, Catalog, Vanzari)
builder.Services.AddDbContext<DistributieDbContext>(options =>
    options.UseOracle(builder.Configuration.GetConnectionString("DistributieDB")));

builder.Services.AddDbContext<CatalogDbContext>(options =>
    options.UseOracle(builder.Configuration.GetConnectionString("CatalogDB")));

builder.Services.AddDbContext<VanzariDbContext>(options =>
    options.UseOracle(builder.Configuration.GetConnectionString("VanzariDB")));

var app = builder.Build();

// Servire fisiere statice UI din ../ui relativ la directorul de lucru
var uiPath = Path.GetFullPath(Path.Combine(Directory.GetCurrentDirectory(), "..", "ui"));
var uiFiles = new Microsoft.Extensions.FileProviders.PhysicalFileProvider(uiPath);
app.UseDefaultFiles(new DefaultFilesOptions { FileProvider = uiFiles, RequestPath = "" });
app.UseStaticFiles(new StaticFileOptions   { FileProvider = uiFiles, RequestPath = "" });

app.UseCors("AllowAll");

// Cerinta 1: GET clienti din PDB Distributie (paginat + filtrare dupa cod)
app.MapGet("/api/distributie/clienti", async (int? page, int? pageSize, string? search, DistributieDbContext db) =>
{
    int p = page ?? 1;
    int ps = pageSize ?? 20;
    var query = db.Clienti.AsQueryable();

    if (!string.IsNullOrEmpty(search))
        query = query.Where(c => c.CodClient.ToLower().Contains(search.ToLower()));

    query = query.OrderByDescending(c => c.Id);
    var total = await query.CountAsync();
    var data  = await query.Skip((p - 1) * ps).Take(ps).ToListAsync();

    return Results.Ok(new { data, total, page = p, pageSize = ps, totalPages = (int)Math.Ceiling((double)total / ps) });
});

// GET zone disponibile din PDB Distributie
app.MapGet("/api/distributie/zone", async (DistributieDbContext db) =>
{
    var zone = await db.Zone.OrderBy(z => z.Id).ToListAsync();
    return Results.Ok(zone);
});

// Cerinta 1: INSERT client nou in PDB Distributie
app.MapPost("/api/distributie/clienti", async (ClientInput input, DistributieDbContext db) =>
{
    long nextId = (await db.Clienti.MaxAsync(c => (long?)c.Id) ?? 0) + 1;

    var client = new Client
    {
        Id             = nextId,
        CodClient      = input.CodClient,
        DenumireClient = input.DenumireClient,
        TipClient      = input.TipClient,
        IdZona         = input.IdZona,
        StartDate      = DateTime.Now,
        EndDate        = input.EndDate
    };

    db.Clienti.Add(client);
    await db.SaveChangesAsync();
    return Results.Created("/api/distributie/clienti", client);
});

// Cerinta 1: UPDATE client existent in PDB Distributie
app.MapPut("/api/distributie/clienti/{id}", async (long id, ClientInput input, DistributieDbContext db) =>
{
    var client = await db.Clienti.FindAsync(id);
    if (client is null) return Results.NotFound();

    client.CodClient      = input.CodClient;
    client.DenumireClient = input.DenumireClient;
    client.TipClient      = input.TipClient;
    client.IdZona         = input.IdZona;
    client.EndDate        = input.EndDate;

    await db.SaveChangesAsync();
    return Results.Ok(client);
});

// Cerinta 1: DELETE client + cascade linii/fise in PDB Vanzari (pe tabele fizice, evita trigger INSTEAD OF)
app.MapDelete("/api/distributie/clienti/{id}", async (long id, DistributieDbContext db, VanzariDbContext vanzariDb) =>
{
    var client = await db.Clienti.FindAsync(id);
    if (client is null) return Results.NotFound();
    try
    {
        var roDocNrs  = await vanzariDb.FiseRo.Where(f => f.CodClient == client.CodClient).Select(f => f.NrDocument).ToListAsync();
        var extDocNrs = await vanzariDb.FiseExt.Where(f => f.CodClient == client.CodClient).Select(f => f.NrDocument).ToListAsync();

        if (roDocNrs.Any())  await vanzariDb.LiniiRo.Where(l => roDocNrs.Contains(l.NrDocument)).ExecuteDeleteAsync();
        if (extDocNrs.Any()) await vanzariDb.LiniiExt.Where(l => extDocNrs.Contains(l.NrDocument)).ExecuteDeleteAsync();

        await vanzariDb.FiseRo.Where(f => f.CodClient == client.CodClient).ExecuteDeleteAsync();
        await vanzariDb.FiseExt.Where(f => f.CodClient == client.CodClient).ExecuteDeleteAsync();
        await db.Contacte.Where(c => c.CodClient == client.CodClient).ExecuteDeleteAsync();

        db.Clienti.Remove(client);
        await db.SaveChangesAsync();
        return Results.NoContent();
    }
    catch (Exception ex)
    {
        return Results.Json(new { error = "Nu se poate sterge clientul. Eroare: " + (ex.InnerException?.Message ?? ex.Message) }, statusCode: 400);
    }
});

// Cerinta 2: GET produse globale via JOIN ITEMS_CORE + ITEMS_EXTRA (V_ITEMS nu exista in sgbd_catalog)
app.MapGet("/api/global/items", async (int? page, int? pageSize, CatalogDbContext db) =>
{
    int p = page ?? 1;
    int ps = pageSize ?? 20;

    var query = db.ItemsCore
        .Join(db.ItemsExtra,
            core  => core.Id,
            extra => extra.Id,
            (core, extra) => new
            {
                core.Id,
                core.ItemCode,
                core.ItemName,
                extra.ItemDescription,
                core.BrandId,
                core.SeasonId,
                core.ItemTypeId,
                core.CategoryId,
                extra.Vat,
                extra.LastCostPrice,
                extra.MainBarcode,
                extra.SupplierCode,
                extra.Weight,
                extra.Um,
                core.Active
            })
        .OrderByDescending(i => i.Id);

    var total = await query.CountAsync();
    var data  = await query.Skip((p - 1) * ps).Take(ps).ToListAsync();

    return Results.Ok(new { data, total, page = p, pageSize = ps, totalPages = (int)Math.Ceiling((double)total / ps) });
});

// Cerinta 4: INSERT produs global direct in ITEMS_CORE si ITEMS_EXTRA
app.MapPost("/api/global/items", async (ItemInput input, CatalogDbContext db) =>
{
    long nextId = (await db.ItemsCore.MaxAsync(i => (long?)i.Id) ?? 0) + 1;

    var core = new ItemCore
    {
        Id         = nextId,
        ItemCode   = input.ItemCode,
        ItemName   = input.ItemName,
        BrandId    = input.BrandId,
        SeasonId   = input.SeasonId,
        ItemTypeId = input.ItemTypeId,
        CategoryId = input.CategoryId,
        Active     = input.Active ?? 1
    };
    var extra = new ItemExtra
    {
        Id              = nextId,
        ItemDescription = input.ItemDescription,
        Vat             = input.Vat,
        LastCostPrice   = input.LastCostPrice,
        MainBarcode     = input.MainBarcode,
        SupplierCode    = input.SupplierCode,
        Weight          = input.Weight,
        Um              = input.Um
    };

    db.ItemsCore.Add(core);
    db.ItemsExtra.Add(extra);
    await db.SaveChangesAsync();

    return Results.Created("/api/global/items", new {
        core.Id, core.ItemCode, core.ItemName,
        extra.ItemDescription, core.BrandId, core.SeasonId,
        core.ItemTypeId, core.CategoryId, extra.Vat,
        extra.LastCostPrice, extra.MainBarcode, extra.SupplierCode,
        extra.Weight, extra.Um, core.Active
    });
});

// Cerinta 4: UPDATE produs global direct in ITEMS_CORE si ITEMS_EXTRA
app.MapPut("/api/global/items/{id}", async (long id, ItemInput input, CatalogDbContext db) =>
{
    var core  = await db.ItemsCore.FindAsync(id);
    var extra = await db.ItemsExtra.FindAsync(id);
    if (core is null) return Results.NotFound();

    core.ItemCode   = input.ItemCode;
    core.ItemName   = input.ItemName;
    core.BrandId    = input.BrandId;
    core.SeasonId   = input.SeasonId;
    core.ItemTypeId = input.ItemTypeId;
    core.CategoryId = input.CategoryId;
    core.Active     = input.Active ?? core.Active;

    if (extra is not null)
    {
        extra.ItemDescription = input.ItemDescription;
        extra.Vat             = input.Vat;
        extra.LastCostPrice   = input.LastCostPrice;
        extra.MainBarcode     = input.MainBarcode;
        extra.SupplierCode    = input.SupplierCode;
        extra.Weight          = input.Weight;
        extra.Um              = input.Um;
    }

    await db.SaveChangesAsync();
    return Results.Ok(new {
        core.Id, core.ItemCode, core.ItemName,
        extra?.ItemDescription, core.BrandId, core.SeasonId,
        core.ItemTypeId, core.CategoryId, extra?.Vat,
        extra?.LastCostPrice, extra?.MainBarcode, extra?.SupplierCode,
        extra?.Weight, extra?.Um, core.Active
    });
});

// Cerinta 2: GET facturi globale via V_FISE_CLIENTI (UNION ALL fise_ro + fise_ext)
app.MapGet("/api/global/fise", async (int? page, int? pageSize, string? search, VanzariDbContext db) =>
{
    int p = page ?? 1;
    int ps = pageSize ?? 20;
    var query = db.Fise.AsQueryable();

    if (!string.IsNullOrEmpty(search))
        query = query.Where(f => f.NrDocument.ToLower().Contains(search.ToLower()));

    query = query.OrderByDescending(f => f.Id);
    var total = await query.CountAsync();
    var data  = await query.Skip((p - 1) * ps).Take(ps).ToListAsync();

    return Results.Ok(new { data, total, page = p, pageSize = ps, totalPages = (int)Math.Ceiling((double)total / ps) });
});

// Cerinta 4: INSERT factura globala via V_FISE_CLIENTI (trigger INSTEAD OF roteaza dupa moneda)
app.MapPost("/api/global/fise", async (FisaInput input, VanzariDbContext db) =>
{
    long nextId = (await db.Fise.MaxAsync(f => (long?)f.Id) ?? 0) + 1;

    var fisa = new GlobalFisa
    {
        Id              = nextId,
        NrDocument      = input.NrDocument,
        NrDocInitial    = input.NrDocInitial,
        DocType         = input.DocType,
        Moneda          = input.Moneda,
        Amount          = input.Amount,
        AmountRon       = input.Amount,
        CodClient       = input.CodClient ?? "CLI000001",
        DataDocEfectiva = DateTime.Now,
        DataScad        = input.DataScad,
        PlataPrin       = input.PlataPrin
    };

    db.Fise.Add(fisa);
    await db.SaveChangesAsync();
    return Results.Created("/api/global/fise", fisa);
});

// Cerinta 1: GET fragment vertical ITEMS_CORE (identitate + clasificare)
app.MapGet("/api/catalog/items-core", async (int? page, int? pageSize, CatalogDbContext db) =>
{
    int p = page ?? 1;
    int ps = pageSize ?? 15;
    var query = db.ItemsCore.OrderByDescending(i => i.Id);
    var total = await query.CountAsync();
    var data  = await query.Skip((p - 1) * ps).Take(ps).ToListAsync();
    return Results.Ok(new { data, total, page = p, pageSize = ps, totalPages = (int)Math.Ceiling((double)total / ps) });
});

// Cerinta 1: GET fragment vertical ITEMS_EXTRA (atribute comerciale + fizice)
app.MapGet("/api/catalog/items-extra", async (int? page, int? pageSize, CatalogDbContext db) =>
{
    int p = page ?? 1;
    int ps = pageSize ?? 15;
    var query = db.ItemsExtra.OrderByDescending(i => i.Id);
    var total = await query.CountAsync();
    var data  = await query.Skip((p - 1) * ps).Take(ps).ToListAsync();
    return Results.Ok(new { data, total, page = p, pageSize = ps, totalPages = (int)Math.Ceiling((double)total / ps) });
});

// Cerinta 3: UPDATE direct pe ITEMS_CORE (transparenta verticala)
app.MapPut("/api/catalog/items-core/{id}", async (long id, ItemCore input, CatalogDbContext db) =>
{
    var item = await db.ItemsCore.FindAsync(id);
    if (item is null) return Results.NotFound();
    item.ItemCode = input.ItemCode;
    item.ItemName = input.ItemName;
    item.Active   = input.Active;
    await db.SaveChangesAsync();
    return Results.Ok(item);
});

// Cerinta 1: DELETE produs + cascade toate documentele care il contin (pe tabele fizice)
app.MapDelete("/api/catalog/items-core/{id}", async (long id, CatalogDbContext db, VanzariDbContext vanzariDb) =>
{
    var item = await db.ItemsCore.FindAsync(id);
    if (item is null) return Results.NotFound();

    try
    {
        var roDocNrs  = await vanzariDb.LiniiRo.Where(l => l.ItemCode == item.ItemCode).Select(l => l.NrDocument).Distinct().ToListAsync();
        var extDocNrs = await vanzariDb.LiniiExt.Where(l => l.ItemCode == item.ItemCode).Select(l => l.NrDocument).Distinct().ToListAsync();

        if (roDocNrs.Any())  await vanzariDb.LiniiRo.Where(l => roDocNrs.Contains(l.NrDocument)).ExecuteDeleteAsync();
        if (extDocNrs.Any()) await vanzariDb.LiniiExt.Where(l => extDocNrs.Contains(l.NrDocument)).ExecuteDeleteAsync();
        if (roDocNrs.Any())  await vanzariDb.FiseRo.Where(f => roDocNrs.Contains(f.NrDocument)).ExecuteDeleteAsync();
        if (extDocNrs.Any()) await vanzariDb.FiseExt.Where(f => extDocNrs.Contains(f.NrDocument)).ExecuteDeleteAsync();

        db.ItemsCore.Remove(item);
        await db.SaveChangesAsync();
        return Results.NoContent();
    }
    catch (Exception ex)
    {
        return Results.Json(new { error = "Nu se poate sterge produsul. Eroare: " + (ex.InnerException?.Message ?? ex.Message) }, statusCode: 400);
    }
});

// Cerinta 1: GET fragment orizontal FISE_CLIENTI_RO (moneda = RON)
app.MapGet("/api/vanzari/fise-ro", async (int? page, int? pageSize, string? search, VanzariDbContext db) =>
{
    int p = page ?? 1;
    int ps = pageSize ?? 15;
    var query = db.FiseRo.AsQueryable();
    if (!string.IsNullOrEmpty(search))
        query = query.Where(f => f.NrDocument.ToLower().Contains(search.ToLower()));
    query = query.OrderByDescending(f => f.Id);
    var total = await query.CountAsync();
    var data  = await query.Skip((p - 1) * ps).Take(ps).ToListAsync();
    return Results.Ok(new { data, total, page = p, pageSize = ps, totalPages = (int)Math.Ceiling((double)total / ps) });
});

// Cerinta 1: GET fragment orizontal FISE_CLIENTI_EXT (moneda <> RON)
app.MapGet("/api/vanzari/fise-ext", async (int? page, int? pageSize, string? search, VanzariDbContext db) =>
{
    int p = page ?? 1;
    int ps = pageSize ?? 15;
    var query = db.FiseExt.AsQueryable();
    if (!string.IsNullOrEmpty(search))
        query = query.Where(f => f.NrDocument.ToLower().Contains(search.ToLower()));
    query = query.OrderByDescending(f => f.Id);
    var total = await query.CountAsync();
    var data  = await query.Skip((p - 1) * ps).Take(ps).ToListAsync();
    return Results.Ok(new { data, total, page = p, pageSize = ps, totalPages = (int)Math.Ceiling((double)total / ps) });
});

// Cerinta 2: GET linii documente globale via V_LINII_DOC (UNION ALL linii_doc_ro + linii_doc_ext)
app.MapGet("/api/global/linii", async (int? page, int? pageSize, VanzariDbContext db) =>
{
    int p = page ?? 1;
    int ps = pageSize ?? 15;
    var query = db.Linii.OrderByDescending(l => l.Id);
    var total = await query.CountAsync();
    var data  = await query.Skip((p - 1) * ps).Take(ps).ToListAsync();
    return Results.Ok(new { data, total, page = p, pageSize = ps, totalPages = (int)Math.Ceiling((double)total / ps) });
});

// Cerinta 3: GET replica MV_CLIENTI din PDB Vanzari
app.MapGet("/api/vanzari/mv-clienti", async (int? page, int? pageSize, VanzariDbContext db) =>
{
    int p = page ?? 1;
    int ps = pageSize ?? 15;
    var query = db.MvClienti.OrderByDescending(c => c.Id);
    var total = await query.CountAsync();
    var data  = await query.Skip((p - 1) * ps).Take(ps).ToListAsync();
    return Results.Ok(new { data, total, page = p, pageSize = ps, totalPages = (int)Math.Ceiling((double)total / ps) });
});

// Cerinta 3: GET replica MV_ITEMS_CORE din PDB Vanzari
app.MapGet("/api/vanzari/mv-items-core", async (int? page, int? pageSize, VanzariDbContext db) =>
{
    int p = page ?? 1;
    int ps = pageSize ?? 15;
    var query = db.MvItemsCore.OrderByDescending(c => c.Id);
    var total = await query.CountAsync();
    var data  = await query.Skip((p - 1) * ps).Take(ps).ToListAsync();
    return Results.Ok(new { data, total, page = p, pageSize = ps, totalPages = (int)Math.Ceiling((double)total / ps) });
});

// Cerinta 3: Refresh MV-uri via job scheduler
app.MapPost("/api/admin/refresh-mv", async (VanzariDbContext db) =>
{
    try
    {
        await db.Database.ExecuteSqlRawAsync(@"
            BEGIN
                DBMS_SCHEDULER.RUN_JOB('JOB_REFRESH_MVS', use_current_session => TRUE);
            END;");
        return Results.Ok(new { message = "MV-urile au fost actualizate cu succes." });
    }
    catch (Exception ex)
    {
        return Results.Json(new { error = ex.Message }, statusCode: 500);
    }
});

// Cerinta 4: INSERT atomic document + linii via INSERT ALL (trigger coerenta AFTER STATEMENT)
app.MapPost("/api/global/documents", async (DocumentWithLinesInput input, VanzariDbContext db) =>
{
    using var tx = await db.Database.BeginTransactionAsync();
    try
    {
        long headerId    = (await db.Fise.MaxAsync(f => (long?)f.Id) ?? 0) + 1;
        long lineIdStart = (await db.Database
            .SqlQueryRaw<long>("SELECT NVL(MAX(id), 0) AS Value FROM v_linii_doc")
            .FirstAsync()) + 1;

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

        if (input.Linii.Count > 0)
        {
            var sb = new StringBuilder("INSERT ALL\n");
            var parameters = new List<OracleParameter>();
            int pIdx = 0;
            int lineOffset = 0;

            foreach (var linie in input.Linii)
            {
                int idP      = pIdx++;
                int docP     = pIdx++;
                int nrP      = pIdx++;
                int itemP    = pIdx++;
                int qtyP     = pIdx++;
                int docValP  = pIdx++;
                int docTvaP  = pIdx++;
                int docPctP  = pIdx++;
                int docTotP  = pIdx++;
                int linWvatP = pIdx++;
                int linValP  = pIdx++;
                int linTvaP  = pIdx++;
                int linPctP  = pIdx++;

                sb.AppendLine($@"  INTO v_linii_doc (
                    id, doc_type_xrp, nr_document, item_code, item_qty,
                    xrp_doc_valoare_fara_tva, xrp_doc_tva, xrp_doc_procent_tva, xrp_doc_valoare_totala,
                    xrp_linie_is_with_vat, xrp_linie_valoare_fara_tva, xrp_linie_tva, xrp_linie_proc_tva
                ) VALUES (
                    :p{idP}, :p{docP}, :p{nrP}, :p{itemP}, :p{qtyP},
                    :p{docValP}, :p{docTvaP}, :p{docPctP}, :p{docTotP},
                    :p{linWvatP}, :p{linValP}, :p{linTvaP}, :p{linPctP}
                )");

                decimal procentTva          = linie.ProcentTva ?? (linie.ValoareFaraTva > 0 ? Math.Round(linie.Tva / linie.ValoareFaraTva * 100, 2) : 0);
                decimal valoareTotala       = linie.ValoareFaraTva + linie.Tva;
                decimal linieValoareFaraTva = linie.LinieValoareFaraTva ?? linie.ValoareFaraTva;
                decimal linieTva            = linie.LinieTva ?? linie.Tva;
                decimal linieProcTva        = linie.LinieProcTva ?? procentTva;
                string  linieIsWithVat      = linie.LinieIsWithVat ?? (linie.Tva > 0 ? "Y" : "N");

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
            await db.Database.ExecuteSqlRawAsync(sb.ToString(), parameters.ToArray());
        }

        await tx.CommitAsync();

        return Results.Created($"/api/global/documents/{headerId}", new
        {
            id         = headerId,
            nrDocument = input.NrDocument,
            moneda     = input.Moneda,
            amount     = input.Amount,
            nrLinii    = input.Linii.Count,
            message    = $"Document {input.NrDocument} salvat cu {input.Linii.Count} linii. " +
                         $"Ruta automat in fragment {(input.Moneda == "RON" ? "RO" : "EXT")}."
        });
    }
    catch (Exception ex)
    {
        await tx.RollbackAsync();

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
