using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace ModbdApi.Models
{
    [Table("MV_CLIENTI")]
    public class MvClient
    {
        [Key, DatabaseGenerated(DatabaseGeneratedOption.None)]
        [Column("ID")]
        public long Id { get; set; }
        
        [Column("COD_CLIENT")]
        public string CodClient { get; set; } = "";
        
        [Column("DENUMIRE_CLIENT")]
        public string DenumireClient { get; set; } = "";
        
        [Column("TIP_CLIENT")]
        public string TipClient { get; set; } = "";
        
        [Column("ID_ZONA")]
        public long IdZona { get; set; }
        
        [Column("START_DATE")]
        public DateTime StartDate { get; set; }

        [Column("END_DATE")]
        public DateTime? EndDate { get; set; }
    }
}
