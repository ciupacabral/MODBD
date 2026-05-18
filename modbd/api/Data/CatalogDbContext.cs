using Microsoft.EntityFrameworkCore;
using ModbdApi.Models;

namespace ModbdApi.Data
{
    public class CatalogDbContext : DbContext
    {
        public CatalogDbContext(DbContextOptions<CatalogDbContext> options) : base(options) {}
        
        public DbSet<GlobalItem> Items { get; set; }
    }
}
