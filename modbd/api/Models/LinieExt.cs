using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace ModbdApi.Models
{
    [Table("LINII_DOC_EXT")]
    public class LinieExt
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

        [Column("XRP_DOC_PROCENT_TVA")]
        public decimal? ProcentTva { get; set; }

        [Column("XRP_DOC_VALOARE_TOTALA")]
        public decimal? ValoareTotala { get; set; }

        [Column("XRP_LINIE_IS_WITH_VAT")]
        public string? LinieIsWithVat { get; set; }

        [Column("XRP_LINIE_VALOARE_FARA_TVA")]
        public decimal? LinieValoareFaraTva { get; set; }

        [Column("XRP_LINIE_TVA")]
        public decimal? LinieTva { get; set; }

        [Column("XRP_LINIE_PROC_TVA")]
        public decimal? LinieProcTva { get; set; }
    }
}
