using Microsoft.EntityFrameworkCore;
using ModbdApi.Models;

namespace ModbdApi.Data
{
    public class VanzariDbContext : DbContext
    {
        public VanzariDbContext(DbContextOptions<VanzariDbContext> options) : base(options) {}
        
        public DbSet<GlobalFisa> Fise { get; set; }
        public DbSet<FisaRo> FiseRo { get; set; }
        public DbSet<FisaExt> FiseExt { get; set; }
        public DbSet<GlobalLinie> Linii { get; set; }
        public DbSet<MvClient> MvClienti { get; set; }
        public DbSet<MvItemCore> MvItemsCore { get; set; }
    }
}
