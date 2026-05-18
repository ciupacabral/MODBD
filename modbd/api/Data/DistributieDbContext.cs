using Microsoft.EntityFrameworkCore;
using ModbdApi.Models;

namespace ModbdApi.Data
{
    public class DistributieDbContext : DbContext
    {
        public DistributieDbContext(DbContextOptions<DistributieDbContext> options) : base(options) {}
        
        public DbSet<Client> Clienti { get; set; }
        public DbSet<Zona> Zone { get; set; }
    }
}
