-- =============================================================================
-- 18_db_links.sql
-- DB links private din VANZARI catre DISTRIBUTIE si CATALOG.
-- Conectare via EZCONNECT (host:port/service_name) catre celelalte PDB-uri.
-- Link-urile sunt PRIVATE (per-user in schema sgbd_vanzari) ca sa evitam
-- conflicte de credentiale globale.
-- =============================================================================


-- ============================================================================
-- Link catre PDB-ul DISTRIBUTIE (CRM, master pentru clienti + zone)
-- ============================================================================
CREATE DATABASE LINK lnk_distributie
    CONNECT TO sgbd_distributie
    IDENTIFIED BY oracle
    USING 'localhost:1521/DISTRIBUTIE';


-- ============================================================================
-- Link catre PDB-ul CATALOG (produse, master pentru items + lookups)
-- ============================================================================
CREATE DATABASE LINK lnk_catalog
    CONNECT TO sgbd_catalog
    IDENTIFIED BY oracle
    USING 'localhost:1521/CATALOG';
