using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace ModbdApi.Models
{
    [Table("V_LINII_DOC")]
    public class GlobalLinie
    {
        [Key, DatabaseGenerated(DatabaseGeneratedOption.None)]
        [Column("ID")]
        public long Id { get; set; }
        
        [Column("DOC_TYPE_XRP")]
        public string DocTypeXrp { get; set; } = "";
        
        [Column("NR_DOCUMENT")]
        public string NrDocument { get; set; } = "";
        
        [Column("ITEM_CODE")]
        public string ItemCode { get; set; } = "";
        
        [Column("ITEM_QTY")]
        public decimal? ItemQty { get; set; }
        
        [Column("XRP_DOC_VALOARE_FARA_TVA")]
        public decimal? ValoareFaraTva { get; set; }
        
        [Column("XRP_DOC_TVA")]
        public decimal? Tva { get; set; }
        
        [Column("XRP_DOC_VALOARE_TOTALA")]
        public decimal? ValoareTotala { get; set; }
    }
}
