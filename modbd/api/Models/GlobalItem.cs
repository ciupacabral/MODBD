using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace ModbdApi.Models
{
    [Table("V_ITEMS")]
    public class GlobalItem
    {
        [Key, DatabaseGenerated(DatabaseGeneratedOption.None)]
        [Column("ID")]
        public long Id { get; set; }

        [Column("ITEM_CODE")]
        public string ItemCode { get; set; } = "";

        [Column("ITEM_NAME")]
        public string ItemName { get; set; } = "";

        [Column("ITEM_DESCRIPTION")]
        public string? ItemDescription { get; set; }

        [Column("BRAND_ID")]
        public long? BrandId { get; set; }

        [Column("SEASON_ID")]
        public long? SeasonId { get; set; }

        [Column("ITEM_TYPE_ID")]
        public long? ItemTypeId { get; set; }

        [Column("CATEGORY_ID")]
        public long? CategoryId { get; set; }

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

        [Column("ACTIVE")]
        public int? Active { get; set; }
    }
}
