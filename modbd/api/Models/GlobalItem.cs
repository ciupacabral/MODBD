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
        public string? Description { get; set; }
        
        [Column("ACTIVE")]
        public int Active { get; set; }
    }
}
