using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace ModbdApi.Models
{
    [Table("ITEMS_EXTRA")]
    public class ItemExtra
    {
        [Key, DatabaseGenerated(DatabaseGeneratedOption.None)]
        [Column("ID")]
        public long Id { get; set; }
        
        [Column("ITEM_DESCRIPTION")]
        public string? ItemDescription { get; set; }
        
        [Column("VAT")]
        public double? Vat { get; set; }
        
        [Column("LAST_COST_PRICE")]
        public decimal? LastCostPrice { get; set; }
        
        [Column("MAIN_BARCODE")]
        public string? MainBarcode { get; set; }
        
        [Column("SUPPLIER_CODE")]
        public string? SupplierCode { get; set; }
        
        [Column("WEIGHT")]
        public decimal? Weight { get; set; }
        
        [Column("UM")]
        public string? Um { get; set; }
    }
}
