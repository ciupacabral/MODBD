-- =============================================================================
-- 02_create_users.sql
-- Pentru fiecare PDB (DISTRIBUTIE / CATALOG / VANZARI):
--   1. Creeaza tablespace USERS (idempotent)
--   2. Cleanup utilizatori vechi (idempotent, ignora daca nu exista)
--   3. Creeaza role `sgbd_role` cu grant-urile standard
--   4. Creeaza user `sgbd_<pdbname>` cu parola `oracle`
-- Toate blocurile sunt idempotente => poate fi rulat de mai multe ori in siguranta.
-- =============================================================================


WHENEVER SQLERROR EXIT SQL.SQLCODE


-- ============================================================================
-- DISTRIBUTIE
-- ============================================================================
ALTER SESSION SET CONTAINER = DISTRIBUTIE;


-- (1) Tablespace USERS — idempotent
DECLARE
    tbs_exists EXCEPTION;
    PRAGMA EXCEPTION_INIT (tbs_exists, -1543);
BEGIN
    EXECUTE IMMEDIATE q'[
        CREATE TABLESPACE users
            DATAFILE '/opt/oracle/oradata/XE/distributie/users01.dbf'
            SIZE 100M
            AUTOEXTEND ON NEXT 50M MAXSIZE 2G
    ]';
EXCEPTION
    WHEN tbs_exists THEN NULL;
END;
/

ALTER DATABASE DEFAULT TABLESPACE users;


-- (2) Cleanup useri vechi — idempotent
DECLARE
    user_not_found EXCEPTION;
    PRAGMA EXCEPTION_INIT (user_not_found, -1918);
BEGIN
    EXECUTE IMMEDIATE 'DROP USER app_dist CASCADE';
EXCEPTION
    WHEN user_not_found THEN NULL;
END;
/

DECLARE
    user_not_found EXCEPTION;
    PRAGMA EXCEPTION_INIT (user_not_found, -1918);
BEGIN
    EXECUTE IMMEDIATE 'DROP USER sgbd_distributie CASCADE';
EXCEPTION
    WHEN user_not_found THEN NULL;
END;
/


-- (3) Role sgbd_role — idempotent
DECLARE
    role_exists EXCEPTION;
    PRAGMA EXCEPTION_INIT (role_exists, -1921);
BEGIN
    EXECUTE IMMEDIATE 'CREATE ROLE sgbd_role';
EXCEPTION
    WHEN role_exists THEN NULL;
END;
/

GRANT connect                     TO sgbd_role;
GRANT resource                    TO sgbd_role;
GRANT create table                TO sgbd_role;
GRANT create view                 TO sgbd_role;
GRANT create materialized view    TO sgbd_role;
GRANT create synonym              TO sgbd_role;
GRANT create procedure            TO sgbd_role;
GRANT create sequence             TO sgbd_role;
GRANT create trigger              TO sgbd_role;
GRANT create type                 TO sgbd_role;
GRANT query rewrite               TO sgbd_role;
GRANT select_catalog_role         TO sgbd_role;
GRANT alter session               TO sgbd_role;
GRANT select any dictionary       TO sgbd_role;
GRANT create database link        TO sgbd_role;
GRANT create public database link TO sgbd_role;
GRANT create public synonym       TO sgbd_role;


-- (4) User aplicativ
CREATE USER sgbd_distributie IDENTIFIED BY oracle
    PROFILE            default
    DEFAULT TABLESPACE users
    QUOTA UNLIMITED ON users
    ACCOUNT UNLOCK;

GRANT sgbd_role            TO sgbd_distributie;
GRANT UNLIMITED TABLESPACE TO sgbd_distributie;


-- ============================================================================
-- CATALOG
-- ============================================================================
ALTER SESSION SET CONTAINER = CATALOG;


DECLARE
    tbs_exists EXCEPTION;
    PRAGMA EXCEPTION_INIT (tbs_exists, -1543);
BEGIN
    EXECUTE IMMEDIATE q'[
        CREATE TABLESPACE users
            DATAFILE '/opt/oracle/oradata/XE/catalog/users01.dbf'
            SIZE 100M
            AUTOEXTEND ON NEXT 50M MAXSIZE 2G
    ]';
EXCEPTION
    WHEN tbs_exists THEN NULL;
END;
/

ALTER DATABASE DEFAULT TABLESPACE users;


DECLARE
    user_not_found EXCEPTION;
    PRAGMA EXCEPTION_INIT (user_not_found, -1918);
BEGIN
    EXECUTE IMMEDIATE 'DROP USER app_cat CASCADE';
EXCEPTION
    WHEN user_not_found THEN NULL;
END;
/

DECLARE
    user_not_found EXCEPTION;
    PRAGMA EXCEPTION_INIT (user_not_found, -1918);
BEGIN
    EXECUTE IMMEDIATE 'DROP USER sgbd_catalog CASCADE';
EXCEPTION
    WHEN user_not_found THEN NULL;
END;
/


DECLARE
    role_exists EXCEPTION;
    PRAGMA EXCEPTION_INIT (role_exists, -1921);
BEGIN
    EXECUTE IMMEDIATE 'CREATE ROLE sgbd_role';
EXCEPTION
    WHEN role_exists THEN NULL;
END;
/

GRANT connect                     TO sgbd_role;
GRANT resource                    TO sgbd_role;
GRANT create table                TO sgbd_role;
GRANT create view                 TO sgbd_role;
GRANT create materialized view    TO sgbd_role;
GRANT create synonym              TO sgbd_role;
GRANT create procedure            TO sgbd_role;
GRANT create sequence             TO sgbd_role;
GRANT create trigger              TO sgbd_role;
GRANT create type                 TO sgbd_role;
GRANT query rewrite               TO sgbd_role;
GRANT select_catalog_role         TO sgbd_role;
GRANT alter session               TO sgbd_role;
GRANT select any dictionary       TO sgbd_role;
GRANT create database link        TO sgbd_role;
GRANT create public database link TO sgbd_role;
GRANT create public synonym       TO sgbd_role;


CREATE USER sgbd_catalog IDENTIFIED BY oracle
    PROFILE            default
    DEFAULT TABLESPACE users
    QUOTA UNLIMITED ON users
    ACCOUNT UNLOCK;

GRANT sgbd_role            TO sgbd_catalog;
GRANT UNLIMITED TABLESPACE TO sgbd_catalog;


-- ============================================================================
-- VANZARI
-- ============================================================================
ALTER SESSION SET CONTAINER = VANZARI;


DECLARE
    tbs_exists EXCEPTION;
    PRAGMA EXCEPTION_INIT (tbs_exists, -1543);
BEGIN
    EXECUTE IMMEDIATE q'[
        CREATE TABLESPACE users
            DATAFILE '/opt/oracle/oradata/XE/vanzari/users01.dbf'
            SIZE 100M
            AUTOEXTEND ON NEXT 50M MAXSIZE 2G
    ]';
EXCEPTION
    WHEN tbs_exists THEN NULL;
END;
/

ALTER DATABASE DEFAULT TABLESPACE users;


DECLARE
    user_not_found EXCEPTION;
    PRAGMA EXCEPTION_INIT (user_not_found, -1918);
BEGIN
    EXECUTE IMMEDIATE 'DROP USER app_vanz CASCADE';
EXCEPTION
    WHEN user_not_found THEN NULL;
END;
/

DECLARE
    user_not_found EXCEPTION;
    PRAGMA EXCEPTION_INIT (user_not_found, -1918);
BEGIN
    EXECUTE IMMEDIATE 'DROP USER sgbd_vanzari CASCADE';
EXCEPTION
    WHEN user_not_found THEN NULL;
END;
/


DECLARE
    role_exists EXCEPTION;
    PRAGMA EXCEPTION_INIT (role_exists, -1921);
BEGIN
    EXECUTE IMMEDIATE 'CREATE ROLE sgbd_role';
EXCEPTION
    WHEN role_exists THEN NULL;
END;
/

GRANT connect                     TO sgbd_role;
GRANT resource                    TO sgbd_role;
GRANT create table                TO sgbd_role;
GRANT create view                 TO sgbd_role;
GRANT create materialized view    TO sgbd_role;
GRANT create synonym              TO sgbd_role;
GRANT create procedure            TO sgbd_role;
GRANT create sequence             TO sgbd_role;
GRANT create trigger              TO sgbd_role;
GRANT create type                 TO sgbd_role;
GRANT query rewrite               TO sgbd_role;
GRANT select_catalog_role         TO sgbd_role;
GRANT alter session               TO sgbd_role;
GRANT select any dictionary       TO sgbd_role;
GRANT create database link        TO sgbd_role;
GRANT create public database link TO sgbd_role;
GRANT create public synonym       TO sgbd_role;


CREATE USER sgbd_vanzari IDENTIFIED BY oracle
    PROFILE            default
    DEFAULT TABLESPACE users
    QUOTA UNLIMITED ON users
    ACCOUNT UNLOCK;

GRANT sgbd_role            TO sgbd_vanzari;
GRANT UNLIMITED TABLESPACE TO sgbd_vanzari;
