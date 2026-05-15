-- =============================================================================
-- 18_db_links.sql
-- DB links private din VANZARI catre DISTRIBUTIE si CATALOG.
-- Conectare via EZCONNECT (host:port/service_name).
-- =============================================================================

CREATE DATABASE LINK lnk_distributie
  CONNECT TO sgbd_distributie IDENTIFIED BY oracle
  USING 'localhost:1521/DISTRIBUTIE';

CREATE DATABASE LINK lnk_catalog
  CONNECT TO sgbd_catalog IDENTIFIED BY oracle
  USING 'localhost:1521/CATALOG';
