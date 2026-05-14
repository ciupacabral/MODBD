-- =============================================================================
-- 02_create_users.sql
-- Conventia cursului (Lect. dr. Gabriela Mihai / Andrei Alexandru Neagu):
--   - Tablespace USERS in fiecare PDB
--   - Role `sgbd_role` cu grant-urile standard din curs
--   - User `sgbd_<pdbname>` cu parola `oracle`
-- Cele 3 BD-uri locale ale proiectului = cele 3 PDB-uri (DISTRIBUTIE/CATALOG/VANZARI).
-- =============================================================================

-- ---------- DISTRIBUTIE ----------
ALTER SESSION SET CONTAINER = DISTRIBUTIE;

-- Drop user vechi (cream local users curat conform cursului)
DROP USER app_dist CASCADE;

-- Tablespace deja exista din rularile anterioare; daca lipseste, decomenteaza:
-- CREATE TABLESPACE users
--   DATAFILE '/opt/oracle/oradata/XE/distributie/users01.dbf'
--   SIZE 100M AUTOEXTEND ON NEXT 50M MAXSIZE 2G;
-- ALTER DATABASE DEFAULT TABLESPACE users;

CREATE ROLE sgbd_role;
GRANT connect TO sgbd_role;
GRANT resource TO sgbd_role;
GRANT create table TO sgbd_role;
GRANT create view TO sgbd_role;
GRANT create materialized view TO sgbd_role;
GRANT create synonym TO sgbd_role;
GRANT create procedure TO sgbd_role;
GRANT create sequence TO sgbd_role;
GRANT create trigger TO sgbd_role;
GRANT create type TO sgbd_role;
GRANT query rewrite TO sgbd_role;
GRANT select_catalog_role TO sgbd_role;
GRANT alter session TO sgbd_role;
GRANT select any dictionary TO sgbd_role;
GRANT create database link TO sgbd_role;
GRANT create public database link TO sgbd_role;
GRANT create public synonym TO sgbd_role;

CREATE USER sgbd_distributie IDENTIFIED BY oracle
  PROFILE default
  DEFAULT TABLESPACE users
  QUOTA UNLIMITED ON users
  ACCOUNT UNLOCK;
GRANT sgbd_role TO sgbd_distributie;
GRANT UNLIMITED TABLESPACE TO sgbd_distributie;

-- ---------- CATALOG ----------
ALTER SESSION SET CONTAINER = CATALOG;
DROP USER app_cat CASCADE;

CREATE ROLE sgbd_role;
GRANT connect TO sgbd_role;
GRANT resource TO sgbd_role;
GRANT create table TO sgbd_role;
GRANT create view TO sgbd_role;
GRANT create materialized view TO sgbd_role;
GRANT create synonym TO sgbd_role;
GRANT create procedure TO sgbd_role;
GRANT create sequence TO sgbd_role;
GRANT create trigger TO sgbd_role;
GRANT create type TO sgbd_role;
GRANT query rewrite TO sgbd_role;
GRANT select_catalog_role TO sgbd_role;
GRANT alter session TO sgbd_role;
GRANT select any dictionary TO sgbd_role;
GRANT create database link TO sgbd_role;
GRANT create public database link TO sgbd_role;
GRANT create public synonym TO sgbd_role;

CREATE USER sgbd_catalog IDENTIFIED BY oracle
  PROFILE default
  DEFAULT TABLESPACE users
  QUOTA UNLIMITED ON users
  ACCOUNT UNLOCK;
GRANT sgbd_role TO sgbd_catalog;
GRANT UNLIMITED TABLESPACE TO sgbd_catalog;

-- ---------- VANZARI ----------
ALTER SESSION SET CONTAINER = VANZARI;
DROP USER app_vanz CASCADE;

CREATE ROLE sgbd_role;
GRANT connect TO sgbd_role;
GRANT resource TO sgbd_role;
GRANT create table TO sgbd_role;
GRANT create view TO sgbd_role;
GRANT create materialized view TO sgbd_role;
GRANT create synonym TO sgbd_role;
GRANT create procedure TO sgbd_role;
GRANT create sequence TO sgbd_role;
GRANT create trigger TO sgbd_role;
GRANT create type TO sgbd_role;
GRANT query rewrite TO sgbd_role;
GRANT select_catalog_role TO sgbd_role;
GRANT alter session TO sgbd_role;
GRANT select any dictionary TO sgbd_role;
GRANT create database link TO sgbd_role;
GRANT create public database link TO sgbd_role;
GRANT create public synonym TO sgbd_role;

CREATE USER sgbd_vanzari IDENTIFIED BY oracle
  PROFILE default
  DEFAULT TABLESPACE users
  QUOTA UNLIMITED ON users
  ACCOUNT UNLOCK;
GRANT sgbd_role TO sgbd_vanzari;
GRANT UNLIMITED TABLESPACE TO sgbd_vanzari;
