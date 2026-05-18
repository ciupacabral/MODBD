using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace ModbdApi.Models
{
    [Table("CLIENTI_CONTACTE")]
    public class ClientContact
    {
        [Key]
        [Column("COD_CLIENT")]
        public string CodClient { get; set; } = "";
        
        [Column("EMAIL_CLIENT")]
        public string? EmailClient { get; set; }
        
        [Column("EMAIL_AGENT")]
        public string? EmailAgent { get; set; }
    }
}
