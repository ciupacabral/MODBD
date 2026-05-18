using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace ModbdApi.Models
{
    [Table("ITEMS_CORE")]
    public class ItemCore
    {
        [Key, DatabaseGenerated(DatabaseGeneratedOption.None)]
        [Column("ID")]
        public long Id { get; set; }
        
        [Column("ITEM_CODE")]
        public string ItemCode { get; set; } = "";
        
        [Column("ITEM_NAME")]
        public string ItemName { get; set; } = "";
        
        [Column("BRAND_ID")]
        public long? BrandId { get; set; }
        
        [Column("SEASON_ID")]
        public long? SeasonId { get; set; }
        
        [Column("ITEM_TYPE_ID")]
        public long? ItemTypeId { get; set; }
        
        [Column("CATEGORY_ID")]
        public long? CategoryId { get; set; }
        
        [Column("ACTIVE")]
        public int? Active { get; set; }
    }
}
