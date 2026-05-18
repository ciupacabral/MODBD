namespace ModbdApi.DTOs
{
    public class ClientInput 
    { 
        public string CodClient { get; set; } = ""; 
        public string DenumireClient { get; set; } = ""; 
        public string TipClient { get; set; } = "CLIENT"; 
        public long IdZona { get; set; } = 1;
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
        public string DocType { get; set; } = "INV"; 
        public string Moneda { get; set; } = "RON"; 
        public decimal Amount { get; set; } = 0; 
        public string? CodClient { get; set; } 
    }
}
