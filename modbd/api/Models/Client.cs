using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace ModbdApi.Models
{
    [Table("CLIENTI")]
    public class Client
    {
        [Key, DatabaseGenerated(DatabaseGeneratedOption.None)]
        [Column("ID")]
        public long Id { get; set; }
        
        [Column("COD_CLIENT")]
        public string CodClient { get; set; } = "";
        
        [Column("DENUMIRE_CLIENT")]
        public string DenumireClient { get; set; } = "";
        
        [Column("TIP_CLIENT")]
        public string TipClient { get; set; } = "CLIENT";
        
        [Column("ID_ZONA")]
        public long IdZona { get; set; } = 1;
        
        [Column("START_DATE")]
        public DateTime StartDate { get; set; }
    }
}
