using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace ModbdApi.Models
{
    [Table("V_FISE_CLIENTI")]
    public class GlobalFisa
    {
        [Key, DatabaseGenerated(DatabaseGeneratedOption.None)]
        [Column("ID")]
        public long Id { get; set; }
        
        [Column("NR_DOCUMENT")]
        public string NrDocument { get; set; } = "";

        [Column("NR_DOC_INITIAL")]
        public string? NrDocInitial { get; set; }

        [Column("DOC_TYPE_XRP")]
        public string DocType { get; set; } = "INV";
        
        [Column("MONEDA")]
        public string Moneda { get; set; } = "RON";
        
        [Column("AMOUNT_DOC")]
        public decimal Amount { get; set; }
        
        [Column("COD_CLIENT")]
        public string CodClient { get; set; } = "CLIENT_FALS";
        
        [Column("AMOUNT_DOC_RON")]
        public decimal AmountRon { get; set; }
        
        [Column("TIP_DOC")]
        public string TipDoc { get; set; } = "F";
        
        [Column("SEMN")]
        public int Semn { get; set; } = 1;
        
        [Column("DENUMIRE_CLIENT")]
        public string DenumireClient { get; set; } = "Client Generat";
        
        [Column("CLASA_CLIENT")]
        public string ClasaClient { get; set; } = "CLIENT";
        
        [Column("DATA_DOC_EFECTIVA")]
        public DateTime DataDocEfectiva { get; set; }

        [Column("DATA_SCAD")]
        public DateTime? DataScad { get; set; }

        [Column("PLATA_PRIN")]
        public string? PlataPrin { get; set; }
    }
}
