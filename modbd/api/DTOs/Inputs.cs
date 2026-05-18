namespace ModbdApi.DTOs
{
    public class ClientInput
    {
        public string CodClient { get; set; } = "";
        public string DenumireClient { get; set; } = "";
        public string TipClient { get; set; } = "CLIENT";
        public long IdZona { get; set; } = 1;
        public DateTime? EndDate { get; set; }
    }

    public class ItemInput
    {
        public string ItemCode { get; set; } = "";
        public string ItemName { get; set; } = "";
        public string? Description { get; set; }
        public int Active { get; set; } = 1;
    }

    public class FisaInput
    {
        public string NrDocument { get; set; } = "";
        public string? NrDocInitial { get; set; }
        public string DocType { get; set; } = "INV";
        public string Moneda { get; set; } = "RON";
        public decimal Amount { get; set; } = 0;
        public DateTime? DataScad { get; set; }
        public string? PlataPrin { get; set; }
        public string? CodClient { get; set; }
    }

    // O linie din document — folosita pentru INSERT atomic header + linii
    // ValoareFaraTva si Tva sunt cele agregate la nivel de document (XRP_DOC_*).
    // Coloanele de detaliu de linie (XRP_LINIE_*) sunt optionale: daca user-ul nu
    // le completeaza, backend-ul copiaza valorile XRP_DOC_* in cele XRP_LINIE_*
    // (caz uzual pentru documente cu o singura linie sau pentru testing).
    public class LinieInput
    {
        public string ItemCode { get; set; } = "";
        public decimal ItemQty { get; set; } = 1;
        public decimal ValoareFaraTva { get; set; } = 0;
        public decimal Tva { get; set; } = 0;
        public decimal? ProcentTva { get; set; }
        public string? LinieIsWithVat { get; set; }
        public decimal? LinieValoareFaraTva { get; set; }
        public decimal? LinieTva { get; set; }
        public decimal? LinieProcTva { get; set; }
    }

    // Header de document + lista de linii — primit de POST /api/global/documents
    // Backend-ul face INSERT prin V_FISE_CLIENTI (trigger INSTEAD OF ruteaza dupa moneda)
    // urmat de INSERT ALL pe V_LINII_DOC intr-un singur statement, astfel incat
    // trigger-ul agregat de coerenta (sum_doc = sum_linii) gaseste toate liniile
    // deodata si nu ridica fals-pozitiv.
    public class DocumentWithLinesInput
    {
        public string NrDocument { get; set; } = "";
        public string? NrDocInitial { get; set; }
        public string DocType { get; set; } = "INV";
        public string Moneda { get; set; } = "RON";
        public decimal Amount { get; set; } = 0;
        public DateTime? DataScad { get; set; }
        public string? PlataPrin { get; set; }
        public string? CodClient { get; set; }
        public string? DenumireClient { get; set; }
        public string? ClasaClient { get; set; }
        public List<LinieInput> Linii { get; set; } = new();
    }
}
