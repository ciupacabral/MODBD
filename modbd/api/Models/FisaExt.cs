using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace ModbdApi.Models
{
    [Table("FISE_CLIENTI_EXT")]
    public class FisaExt
    {
        [Key, DatabaseGenerated(DatabaseGeneratedOption.None)]
        [Column("ID")]
        public long Id { get; set; }
        
        [Column("NR_DOCUMENT")]
        public string NrDocument { get; set; } = "";
        
        [Column("TIP_DOC")]
        public string TipDoc { get; set; } = "F";
        
        [Column("DOC_TYPE_XRP")]
        public string DocTypeXrp { get; set; } = "INV";
        
        [Column("DATA_DOC_EFECTIVA")]
        public DateTime DataDocEfectiva { get; set; }
        
        [Column("SEMN")]
        public int Semn { get; set; } = 1;
        
        [Column("MONEDA")]
        public string Moneda { get; set; } = "EUR";
        
        [Column("AMOUNT_DOC")]
        public decimal AmountDoc { get; set; }
        
        [Column("AMOUNT_DOC_RON")]
        public decimal AmountDocRon { get; set; }
        
        [Column("COD_CLIENT")]
        public string CodClient { get; set; } = "";
        
        [Column("DENUMIRE_CLIENT")]
        public string DenumireClient { get; set; } = "";
        
        [Column("CLASA_CLIENT")]
        public string ClasaClient { get; set; } = "CLIENT";
    }
}
