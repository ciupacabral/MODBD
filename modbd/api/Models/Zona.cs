using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace ModbdApi.Models
{
    [Table("ZONE")]
    public class Zona
    {
        [Key, DatabaseGenerated(DatabaseGeneratedOption.None)]
        [Column("ID")]
        public long Id { get; set; }
        
        [Column("COD_ZONA")]
        public string CodZona { get; set; } = "";
        
        [Column("DEN_ZONA")]
        public string DenZona { get; set; } = "";
    }
}
