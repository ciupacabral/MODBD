using Microsoft.EntityFrameworkCore;
using ModbdApi.Models;

namespace ModbdApi.Data
{
    public class VanzariDbContext : DbContext
    {
        public VanzariDbContext(DbContextOptions<VanzariDbContext> options) : base(options) {}
        
        public DbSet<GlobalFisa> Fise { get; set; }
    }
}
