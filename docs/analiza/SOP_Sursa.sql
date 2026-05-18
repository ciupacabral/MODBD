--################################################################################
--################################################################################
--
-- PROIECT MODBD
-- ECHIPA SOP - SURSA SQL
-- Membri: Stefan Magureanu, Octavian Oprinoiu, Andrei Pitoiu
--
--################################################################################
--################################################################################


-- =============================================================================
-- Setup.sql - Bootstrap initial pentru proiectul MODBD
-- =============================================================================
-- Pornind de la o BD complet noua (3 PDB-uri inca necreate), acest fisier:
--   1. Creeaza cele 3 PDB-uri (DISTRIBUTIE, CATALOG, VANZARI)
--   2. Creeaza utilizatori app + role + grant-uri
--   3. Creeaza directorul CSV pentru external tables
--   4. Creeaza tabelele pentru fiecare PDB (cu fragmentare built-in)
--   5. Populeaza tabelele cu date din cele 15 CSV-uri
--
-- Rezultat final: 3 PDB-uri cu tabele complete si populate.
-- Fragmentarea (verticala BEA pe ITEMS, orizontala primara pe FISE_CLIENTI,
-- orizontala derivata pe LINII_DOC) este aplicata direct in DDL-ul initial -
-- noi pornim cu o BD distribuita "din proiectare", nu re-organizam o BD
-- pre-existenta.
-- Fisierul contine directive sqlplus
-- =============================================================================
SET SQLBLANKLINES ON
SET ECHO ON
SET SERVEROUTPUT ON
SET LINESIZE 200 WHENEVER SQLERROR

CONTINUE
	-- ============================================================================
	-- RULEAZA CA: sys IN PDB-UL "XE"
	-- Creare PDB-uri, useri, director CSV
	-- ============================================================================
	CONNECT sys / ModbdSecret123@ //localhost:1521/XE as sysdba
	-- ----------------------------------------------------------------------------
	-- Pas 1.1: Creare PDB-uri
	-- ----------------------------------------------------------------------------
	WHENEVER SQLERROR EXIT SQL.SQLCODE

ALTER SESSION

SET CONTAINER = CDB$ROOT;

-- ============================================================================
-- Eliminam PDB-ul default XEPDB1 ca sa eliberam slot.
-- (pentru ca oracle xe accepta doar 3 PDB-uri user)
-- ============================================================================
DECLARE not_exist EXCEPTION;

PRAGMA EXCEPTION_INIT(not_exist, - 65011);

not_open EXCEPTION;

PRAGMA EXCEPTION_INIT(not_open, - 65020);

BEGIN
	BEGIN
		EXECUTE IMMEDIATE 'ALTER PLUGGABLE DATABASE XEPDB1 CLOSE IMMEDIATE';

		EXCEPTION WHEN not_exist THEN NULL;WHEN

		not_open THEN NULL;WHEN

		OTHERS THEN

		IF SQLCODE NOT IN (
				- 65019
				,- 65020
				,- 65011
				) THEN RAISE;END
			IF ;END;
			BEGIN
				EXECUTE IMMEDIATE 'DROP PLUGGABLE DATABASE XEPDB1 INCLUDING DATAFILES';

				EXCEPTION WHEN not_exist THEN NULL;WHEN

				OTHERS THEN

				IF SQLCODE != - 65011 THEN RAISE;END
					IF ;END;END;/
						-- ============================================================================
						-- Creare PDB-uri; pot fi rulate oricum, le creeaza daca nu exista;
						-- ============================================================================
						DECLARE v_exists NUMBER;

				BEGIN
					SELECT COUNT(*)
					INTO v_exists
					FROM v$pdbs
					WHERE name = 'DISTRIBUTIE';

					IF v_exists = 0 THEN
						EXECUTE IMMEDIATE q '[
            CREATE PLUGGABLE DATABASE distributie
                ADMIN USER pdb_admin IDENTIFIED BY "ModbdSecret123"
                FILE_NAME_CONVERT = (
                    ' / opt / oracle / oradata / XE / pdbseed / '
                  , ' / opt / oracle / oradata / XE / distributie / '
                )
        ]';

					EXECUTE IMMEDIATE 'ALTER PLUGGABLE DATABASE distributie OPEN';
				END

				IF ;END;/
					DECLARE v_exists NUMBER;

				BEGIN
					SELECT COUNT(*)
					INTO v_exists
					FROM v$pdbs
					WHERE name = 'CATALOG';

					IF v_exists = 0 THEN
						EXECUTE IMMEDIATE q '[
            CREATE PLUGGABLE DATABASE catalog
                ADMIN USER pdb_admin IDENTIFIED BY "ModbdSecret123"
                FILE_NAME_CONVERT = (
                    ' / opt / oracle / oradata / XE / pdbseed / '
                  , ' / opt / oracle / oradata / XE / CATALOG / '
                )
        ]';

					EXECUTE IMMEDIATE 'ALTER PLUGGABLE DATABASE catalog OPEN';
				END

				IF ;END;/
					DECLARE v_exists NUMBER;

				BEGIN
					SELECT COUNT(*)
					INTO v_exists
					FROM v$pdbs
					WHERE name = 'VANZARI';

					IF v_exists = 0 THEN
						EXECUTE IMMEDIATE q '[
            CREATE PLUGGABLE DATABASE vanzari
                ADMIN USER pdb_admin IDENTIFIED BY "ModbdSecret123"
                FILE_NAME_CONVERT = (
                    ' / opt / oracle / oradata / XE / pdbseed / '
                  , ' / opt / oracle / oradata / XE / vanzari / '
                )
        ]';

					EXECUTE IMMEDIATE 'ALTER PLUGGABLE DATABASE vanzari OPEN';
				END

				IF ;END;/
					ALTER PLUGGABLE DATABASE distributie SAVE STATE;

				ALTER PLUGGABLE DATABASE CATALOG SAVE STATE;

				ALTER PLUGGABLE DATABASE vanzari SAVE STATE;

				-- Verificare finala
				SELECT con_id
					,name
					,open_mode
				FROM v$pdbs
				ORDER BY con_id;

				-- ----------------------------------------------------------------------------
				-- Pas 1.2: Tablespace USERS + utilizatori app + role sgbd_role + grant-uri
				-- ----------------------------------------------------------------------------
				WHENEVER SQLERROR EXIT SQL.SQLCODE

				-- ============================================================================
				-- DISTRIBUTIE
				-- ============================================================================
				ALTER SESSION

				SET CONTAINER = DISTRIBUTIE;

				-- (1) Tablespace USERS
				DECLARE tbs_exists EXCEPTION;

				PRAGMA EXCEPTION_INIT(tbs_exists, - 1543);

				BEGIN
					EXECUTE IMMEDIATE q '[
        CREATE TABLESPACE users
            DATAFILE ' / opt / oracle / oradata / XE / distributie / users01.dbf '
            SIZE 100M
            AUTOEXTEND ON NEXT 50M MAXSIZE 2G
    ]';

					EXCEPTION WHEN tbs_exists THEN NULL;
				END;/

				ALTER DATABASE DEFAULT TABLESPACE users;

				-- (2) Cleanup useri vechi
				DECLARE user_not_found EXCEPTION;

				PRAGMA EXCEPTION_INIT(user_not_found, - 1918);

				BEGIN
					EXECUTE IMMEDIATE 'DROP USER app_dist CASCADE';

					EXCEPTION WHEN user_not_found THEN NULL;
				END;/

				DECLARE user_not_found EXCEPTION;

				PRAGMA EXCEPTION_INIT(user_not_found, - 1918);

				BEGIN
					EXECUTE IMMEDIATE 'DROP USER sgbd_distributie CASCADE';

					EXCEPTION WHEN user_not_found THEN NULL;
				END;/

				-- (3) Role sgbd_role
				DECLARE role_exists EXCEPTION;

				PRAGMA EXCEPTION_INIT(role_exists, - 1921);

				BEGIN
					EXECUTE IMMEDIATE 'CREATE ROLE sgbd_role';

					EXCEPTION WHEN role_exists THEN NULL;
				END;/

				GRANT CONNECT
					TO sgbd_role;

				GRANT RESOURCE
					TO sgbd_role;

				GRANT CREATE TABLE
					TO sgbd_role;

				GRANT CREATE VIEW
					TO sgbd_role;

				GRANT CREATE MATERIALIZED VIEW
					TO sgbd_role;

				GRANT CREATE SYNONYM
					TO sgbd_role;

				GRANT CREATE PROCEDURE
					TO sgbd_role;

				GRANT CREATE SEQUENCE
					TO sgbd_role;

				GRANT CREATE TRIGGER
					TO sgbd_role;

				GRANT CREATE TYPE
					TO sgbd_role;

				GRANT QUERY REWRITE
					TO sgbd_role;

				GRANT SELECT_CATALOG_ROLE
					TO sgbd_role;

				GRANT ALTER SESSION
					TO sgbd_role;

				GRANT SELECT ANY DICTIONARY
					TO sgbd_role;

				GRANT CREATE DATABASE LINK
					TO sgbd_role;

				GRANT CREATE PUBLIC DATABASE LINK
					TO sgbd_role;

				GRANT CREATE PUBLIC SYNONYM
					TO sgbd_role;

				GRANT CREATE JOB
					TO sgbd_role;

				-- (4) User distributie
				CREATE USER sgbd_distributie IDENTIFIED BY oracle PROFILE DEFAULT DEFAULT TABLESPACE users QUOTA UNLIMITED ON users ACCOUNT UNLOCK;

				GRANT SGBD_ROLE
					TO sgbd_distributie;

				GRANT UNLIMITED TABLESPACE
					TO sgbd_distributie;

				-- ============================================================================
				-- CATALOG
				-- ============================================================================
				ALTER SESSION

				SET CONTAINER = CATALOG;

				DECLARE tbs_exists EXCEPTION;

				PRAGMA EXCEPTION_INIT(tbs_exists, - 1543);

				BEGIN
					EXECUTE IMMEDIATE q '[
        CREATE TABLESPACE users
            DATAFILE ' / opt / oracle / oradata / XE / CATALOG / users01.dbf '
            SIZE 100M
            AUTOEXTEND ON NEXT 50M MAXSIZE 2G
    ]';

					EXCEPTION WHEN tbs_exists THEN NULL;
				END;/

				ALTER DATABASE DEFAULT TABLESPACE users;

				DECLARE user_not_found EXCEPTION;

				PRAGMA EXCEPTION_INIT(user_not_found, - 1918);

				BEGIN
					EXECUTE IMMEDIATE 'DROP USER app_cat CASCADE';

					EXCEPTION WHEN user_not_found THEN NULL;
				END;/

				DECLARE user_not_found EXCEPTION;

				PRAGMA EXCEPTION_INIT(user_not_found, - 1918);

				BEGIN
					EXECUTE IMMEDIATE 'DROP USER sgbd_catalog CASCADE';

					EXCEPTION WHEN user_not_found THEN NULL;
				END;/

				DECLARE role_exists EXCEPTION;

				PRAGMA EXCEPTION_INIT(role_exists, - 1921);

				BEGIN
					EXECUTE IMMEDIATE 'CREATE ROLE sgbd_role';

					EXCEPTION WHEN role_exists THEN NULL;
				END;/

				GRANT CONNECT
					TO sgbd_role;

				GRANT RESOURCE
					TO sgbd_role;

				GRANT CREATE TABLE
					TO sgbd_role;

				GRANT CREATE VIEW
					TO sgbd_role;

				GRANT CREATE MATERIALIZED VIEW
					TO sgbd_role;

				GRANT CREATE SYNONYM
					TO sgbd_role;

				GRANT CREATE PROCEDURE
					TO sgbd_role;

				GRANT CREATE SEQUENCE
					TO sgbd_role;

				GRANT CREATE TRIGGER
					TO sgbd_role;

				GRANT CREATE TYPE
					TO sgbd_role;

				GRANT QUERY REWRITE
					TO sgbd_role;

				GRANT SELECT_CATALOG_ROLE
					TO sgbd_role;

				GRANT ALTER SESSION
					TO sgbd_role;

				GRANT SELECT ANY DICTIONARY
					TO sgbd_role;

				GRANT CREATE DATABASE LINK
					TO sgbd_role;

				GRANT CREATE PUBLIC DATABASE LINK
					TO sgbd_role;

				GRANT CREATE PUBLIC SYNONYM
					TO sgbd_role;

				GRANT CREATE JOB
					TO sgbd_role;

				CREATE USER sgbd_catalog IDENTIFIED BY oracle PROFILE DEFAULT DEFAULT TABLESPACE users QUOTA UNLIMITED ON users ACCOUNT UNLOCK;

				GRANT SGBD_ROLE
					TO sgbd_catalog;

				GRANT UNLIMITED TABLESPACE
					TO sgbd_catalog;

				-- ============================================================================
				-- VANZARI
				-- ============================================================================
				ALTER SESSION

				SET CONTAINER = VANZARI;

				DECLARE tbs_exists EXCEPTION;

				PRAGMA EXCEPTION_INIT(tbs_exists, - 1543);

				BEGIN
					EXECUTE IMMEDIATE q '[
        CREATE TABLESPACE users
            DATAFILE ' / opt / oracle / oradata / XE / vanzari / users01.dbf '
            SIZE 100M
            AUTOEXTEND ON NEXT 50M MAXSIZE 2G
    ]';

					EXCEPTION WHEN tbs_exists THEN NULL;
				END;/

				ALTER DATABASE DEFAULT TABLESPACE users;

				DECLARE user_not_found EXCEPTION;

				PRAGMA EXCEPTION_INIT(user_not_found, - 1918);

				BEGIN
					EXECUTE IMMEDIATE 'DROP USER app_vanz CASCADE';

					EXCEPTION WHEN user_not_found THEN NULL;
				END;/

				DECLARE user_not_found EXCEPTION;

				PRAGMA EXCEPTION_INIT(user_not_found, - 1918);

				BEGIN
					EXECUTE IMMEDIATE 'DROP USER sgbd_vanzari CASCADE';

					EXCEPTION WHEN user_not_found THEN NULL;
				END;/

				DECLARE role_exists EXCEPTION;

				PRAGMA EXCEPTION_INIT(role_exists, - 1921);

				BEGIN
					EXECUTE IMMEDIATE 'CREATE ROLE sgbd_role';

					EXCEPTION WHEN role_exists THEN NULL;
				END;/

				GRANT CONNECT
					TO sgbd_role;

				GRANT RESOURCE
					TO sgbd_role;

				GRANT CREATE TABLE
					TO sgbd_role;

				GRANT CREATE VIEW
					TO sgbd_role;

				GRANT CREATE MATERIALIZED VIEW
					TO sgbd_role;

				GRANT CREATE SYNONYM
					TO sgbd_role;

				GRANT CREATE PROCEDURE
					TO sgbd_role;

				GRANT CREATE SEQUENCE
					TO sgbd_role;

				GRANT CREATE TRIGGER
					TO sgbd_role;

				GRANT CREATE TYPE
					TO sgbd_role;

				GRANT QUERY REWRITE
					TO sgbd_role;

				GRANT SELECT_CATALOG_ROLE
					TO sgbd_role;

				GRANT ALTER SESSION
					TO sgbd_role;

				GRANT SELECT ANY DICTIONARY
					TO sgbd_role;

				GRANT CREATE DATABASE LINK
					TO sgbd_role;

				GRANT CREATE PUBLIC DATABASE LINK
					TO sgbd_role;

				GRANT CREATE PUBLIC SYNONYM
					TO sgbd_role;

				GRANT CREATE JOB
					TO sgbd_role;

				CREATE USER sgbd_vanzari IDENTIFIED BY oracle PROFILE DEFAULT DEFAULT TABLESPACE users QUOTA UNLIMITED ON users ACCOUNT UNLOCK;

				GRANT SGBD_ROLE
					TO sgbd_vanzari;

				GRANT UNLIMITED TABLESPACE
					TO sgbd_vanzari;

				-- ----------------------------------------------------------------------------
				-- Pas 1.3: Director CSV_DIR + grant READ
				-- ----------------------------------------------------------------------------
				-- =============================================================================
				-- 03_csv_directory.sql
				-- Creeaza directory object CSV_DIR care trimite la directorul cu fisierele CSV in fiecare
				-- PDB si acorda drept de READ pe el user-ilor
				-- Se ruleaza ca SYS, schimba PDB-uri prin ALTER SESSION.
				-- =============================================================================
				-- ============================================================================
				-- DISTRIBUTIE
				-- ============================================================================
				ALTER SESSION

				SET CONTAINER = DISTRIBUTIE;

				CREATE
					OR REPLACE DIRECTORY csv_dir AS '/csv';

				GRANT READ
					ON DIRECTORY csv_dir
					TO sgbd_distributie;

				-- ============================================================================
				-- CATALOG
				-- ============================================================================
				ALTER SESSION

				SET CONTAINER = CATALOG;

				CREATE
					OR REPLACE DIRECTORY csv_dir AS '/csv';

				GRANT READ
					ON DIRECTORY csv_dir
					TO sgbd_catalog;

				-- ============================================================================
				-- VANZARI
				-- ============================================================================
				ALTER SESSION

				SET CONTAINER = VANZARI;

				CREATE
					OR REPLACE DIRECTORY csv_dir AS '/csv';

				GRANT READ
					ON DIRECTORY csv_dir
					TO sgbd_vanzari;

				-- ============================================================================
				-- RULEAZA CA: sgbd_distributie IN PDB-UL "DISTRIBUTIE"
				-- ============================================================================
				CONNECT sgbd_distributie / oracle@ //localhost:1521/DISTRIBUTIE

				-- ----------------------------------------------------------------------------
				-- Pas 2.1: DDL - 8 tabele master + 8 FK locale
				-- ----------------------------------------------------------------------------
				-- ============================================================================
				-- ZONE: zone comerciale (Int/Ext) + ierarhie self-ref
				-- ============================================================================
				CREATE TABLE zone (
					id NUMBER(19)
					,cod_zona VARCHAR2(40) NOT NULL
					,den_zona VARCHAR2(80) NOT NULL
					,tip_zona VARCHAR2(10) NOT NULL
					,parent_zona_id NUMBER(19)
					,CONSTRAINT pk_zone PRIMARY KEY (id)
					,CONSTRAINT uk_zone_cod UNIQUE (cod_zona)
					,CONSTRAINT fk_zone_parent FOREIGN KEY (parent_zona_id) REFERENCES zone(id)
					);

				-- ============================================================================
				-- AGENTI: agenti vanzari
				-- ============================================================================
				CREATE TABLE agenti (
					id NUMBER(19)
					,cod_agent VARCHAR2(20) NOT NULL
					,nume_agent VARCHAR2(100) NOT NULL
					,email VARCHAR2(200)
					,CONSTRAINT pk_agenti PRIMARY KEY (id)
					,CONSTRAINT uk_agenti_cod UNIQUE (cod_agent)
					);

				-- ============================================================================
				-- CLIENTI: alocati pe zone
				-- ============================================================================
				CREATE TABLE clienti (
					id NUMBER(19)
					,cod_client VARCHAR2(60) NOT NULL
					,denumire_client VARCHAR2(200) NOT NULL
					,tip_client VARCHAR2(12) NOT NULL
					,id_zona NUMBER(19) NOT NULL
					,start_date DATE NOT NULL
					,end_date DATE
					,CONSTRAINT pk_clienti PRIMARY KEY (id)
					,CONSTRAINT uk_clienti_cod UNIQUE (cod_client)
					,CONSTRAINT fk_clienti_zona FOREIGN KEY (id_zona) REFERENCES zone(id)
					,CONSTRAINT ck_clienti_dates CHECK (
						end_date IS NULL
						OR end_date > start_date
						)
					);

				-- ============================================================================
				-- CLIENTI_CONTACTE: email-uri
				-- ============================================================================
				CREATE TABLE clienti_contacte (
					cod_client VARCHAR2(60)
					,email_client VARCHAR2(1000)
					,email_agent VARCHAR2(1000)
					,CONSTRAINT pk_contacte PRIMARY KEY (cod_client)
					,CONSTRAINT fk_contacte_client FOREIGN KEY (cod_client) REFERENCES clienti(cod_client)
					);

				-- ============================================================================
				-- INTERVALE_PLATA: tipuri de termene de plata
				-- ============================================================================
				CREATE TABLE intervale_plata (
					id NUMBER(19)
					,den_interval VARCHAR2(60) NOT NULL
					,CONSTRAINT pk_intpl PRIMARY KEY (id)
					,CONSTRAINT uk_intpl_den UNIQUE (den_interval)
					);

				-- ============================================================================
				-- INTERVALE_PLATA_ZILE: detalii termene
				-- ============================================================================
				CREATE TABLE intervale_plata_zile (
					id_interval NUMBER(19) NOT NULL
					,per_zile VARCHAR2(40) NOT NULL
					,zile_start NUMBER(10) NOT NULL
					,zile_end NUMBER(10)
					,CONSTRAINT pk_intpl_zile PRIMARY KEY (
						id_interval
						,per_zile
						)
					,CONSTRAINT fk_intpl_zile FOREIGN KEY (id_interval) REFERENCES intervale_plata(id)
					);

				-- ============================================================================
				-- ZONE_AGENTI
				-- ============================================================================
				CREATE TABLE zone_agenti (
					id NUMBER(19)
					,id_zona NUMBER(19) NOT NULL
					,id_agent NUMBER(19) NOT NULL
					,start_date DATE NOT NULL
					,end_date DATE
					,CONSTRAINT pk_zone_agenti PRIMARY KEY (id)
					,CONSTRAINT fk_za_zona FOREIGN KEY (id_zona) REFERENCES zone(id)
					,CONSTRAINT fk_za_agent FOREIGN KEY (id_agent) REFERENCES agenti(id)
					,CONSTRAINT ck_za_dates CHECK (
						end_date IS NULL
						OR end_date > start_date
						)
					);

				-- ============================================================================
				-- ZONE_INTERVALE_PLATA: cu istoric
				-- ============================================================================
				CREATE TABLE zone_intervale_plata (
					id NUMBER(19)
					,id_zona NUMBER(19) NOT NULL
					,id_interval NUMBER(19) NOT NULL
					,start_date DATE NOT NULL
					,end_date DATE
					,CONSTRAINT pk_zone_intpl PRIMARY KEY (id)
					,CONSTRAINT fk_zip_zona FOREIGN KEY (id_zona) REFERENCES zone(id)
					,CONSTRAINT fk_zip_interval FOREIGN KEY (id_interval) REFERENCES intervale_plata(id)
					,CONSTRAINT ck_zip_dates CHECK (
						end_date IS NULL
						OR end_date > start_date
						)
					);

				-- ----------------------------------------------------------------------------
				-- Pas 2.2: Load 52 randuri via external tables
				-- ----------------------------------------------------------------------------
				-- ============================================================================
				-- ZONE
				-- ============================================================================
				CREATE TABLE ext_zone (
					id NUMBER(19)
					,cod_zona VARCHAR2(40)
					,den_zona VARCHAR2(80)
					,tip_zona VARCHAR2(10)
					,parent_zona_id VARCHAR2(20)
					) ORGANIZATION EXTERNAL (TYPE ORACLE_LOADER DEFAULT DIRECTORY csv_dir ACCESS PARAMETERS(RECORDS DELIMITED BY NEWLINE CHARACTERSET UTF8 NOLOGFILE NOBADFILE NODISCARDFILE SKIP 1 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LRTRIM MISSING FIELD VALUES ARE NULL) LOCATION('ZONE.csv')) REJECT LIMIT UNLIMITED;

				INSERT INTO zone (
					id
					,cod_zona
					,den_zona
					,tip_zona
					,parent_zona_id
					)
				SELECT id
					,cod_zona
					,den_zona
					,tip_zona
					,CASE 
						WHEN parent_zona_id = 'NULL'
							THEN NULL
						ELSE TO_NUMBER(parent_zona_id)
						END
				FROM ext_zone;

				DROP TABLE ext_zone;

				-- ============================================================================
				-- AGENTI
				-- ============================================================================
				CREATE TABLE ext_agenti (
					id NUMBER(19)
					,cod_agent VARCHAR2(20)
					,nume_agent VARCHAR2(100)
					,email VARCHAR2(200)
					) ORGANIZATION EXTERNAL (TYPE ORACLE_LOADER DEFAULT DIRECTORY csv_dir ACCESS PARAMETERS(RECORDS DELIMITED BY NEWLINE CHARACTERSET UTF8 NOLOGFILE NOBADFILE NODISCARDFILE SKIP 1 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LRTRIM MISSING FIELD VALUES ARE NULL) LOCATION('AGENTI.csv')) REJECT LIMIT UNLIMITED;

				INSERT INTO agenti
				SELECT *
				FROM ext_agenti;

				DROP TABLE ext_agenti;

				-- ============================================================================
				-- CLIENTI
				-- ============================================================================
				CREATE TABLE ext_clienti (
					id NUMBER(19)
					,cod_client VARCHAR2(60)
					,denumire_client VARCHAR2(200)
					,tip_client VARCHAR2(12)
					,id_zona NUMBER(19)
					,start_date VARCHAR2(20)
					,end_date VARCHAR2(20)
					) ORGANIZATION EXTERNAL (TYPE ORACLE_LOADER DEFAULT DIRECTORY csv_dir ACCESS PARAMETERS(RECORDS DELIMITED BY NEWLINE CHARACTERSET UTF8 NOLOGFILE NOBADFILE NODISCARDFILE SKIP 1 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LRTRIM MISSING FIELD VALUES ARE NULL) LOCATION('CLIENTI.csv')) REJECT LIMIT UNLIMITED;

				INSERT INTO clienti (
					id
					,cod_client
					,denumire_client
					,tip_client
					,id_zona
					,start_date
					,end_date
					)
				SELECT id
					,cod_client
					,denumire_client
					,tip_client
					,id_zona
					,TO_DATE(start_date, 'YYYY-MM-DD')
					,CASE 
						WHEN end_date = 'NULL'
							THEN NULL
						ELSE TO_DATE(end_date, 'YYYY-MM-DD')
						END
				FROM ext_clienti;

				DROP TABLE ext_clienti;

				-- ============================================================================
				-- CLIENTI_CONTACTE
				-- ============================================================================
				CREATE TABLE ext_contacte (
					cod_client VARCHAR2(60)
					,email_client VARCHAR2(1000)
					,email_agent VARCHAR2(1000)
					) ORGANIZATION EXTERNAL (TYPE ORACLE_LOADER DEFAULT DIRECTORY csv_dir ACCESS PARAMETERS(RECORDS DELIMITED BY NEWLINE CHARACTERSET UTF8 NOLOGFILE NOBADFILE NODISCARDFILE SKIP 1 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LRTRIM MISSING FIELD VALUES ARE NULL) LOCATION('CONTACTE.csv')) REJECT LIMIT UNLIMITED;

				INSERT INTO clienti_contacte
				SELECT *
				FROM ext_contacte;

				DROP TABLE ext_contacte;

				-- ============================================================================
				-- INTERVALE_PLATA
				-- ============================================================================
				CREATE TABLE ext_intpl (
					id NUMBER(19)
					,den_interval VARCHAR2(60)
					) ORGANIZATION EXTERNAL (TYPE ORACLE_LOADER DEFAULT DIRECTORY csv_dir ACCESS PARAMETERS(RECORDS DELIMITED BY NEWLINE CHARACTERSET UTF8 NOLOGFILE NOBADFILE NODISCARDFILE SKIP 1 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LRTRIM MISSING FIELD VALUES ARE NULL) LOCATION('INTERVALE_PLATA.csv')) REJECT LIMIT UNLIMITED;

				INSERT INTO intervale_plata
				SELECT *
				FROM ext_intpl;

				DROP TABLE ext_intpl;

				-- ============================================================================
				-- INTERVALE_PLATA_ZILE
				-- ============================================================================
				CREATE TABLE ext_intpl_zile (
					id_interval NUMBER(19)
					,per_zile VARCHAR2(40)
					,zile_start NUMBER(10)
					,zile_end VARCHAR2(10)
					) ORGANIZATION EXTERNAL (TYPE ORACLE_LOADER DEFAULT DIRECTORY csv_dir ACCESS PARAMETERS(RECORDS DELIMITED BY NEWLINE CHARACTERSET UTF8 NOLOGFILE NOBADFILE NODISCARDFILE SKIP 1 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LRTRIM MISSING FIELD VALUES ARE NULL) LOCATION('INTERVALE_PLATA_ZILE.csv')) REJECT LIMIT UNLIMITED;

				INSERT INTO intervale_plata_zile (
					id_interval
					,per_zile
					,zile_start
					,zile_end
					)
				SELECT id_interval
					,per_zile
					,zile_start
					,CASE 
						WHEN zile_end = 'NULL'
							THEN NULL
						ELSE TO_NUMBER(zile_end)
						END
				FROM ext_intpl_zile;

				DROP TABLE ext_intpl_zile;

				-- ============================================================================
				-- ZONE_AGENTI
				-- ============================================================================
				CREATE TABLE ext_za (
					id NUMBER(19)
					,id_zona NUMBER(19)
					,id_agent NUMBER(19)
					,start_date VARCHAR2(20)
					,end_date VARCHAR2(20)
					) ORGANIZATION EXTERNAL (TYPE ORACLE_LOADER DEFAULT DIRECTORY csv_dir ACCESS PARAMETERS(RECORDS DELIMITED BY NEWLINE CHARACTERSET UTF8 NOLOGFILE NOBADFILE NODISCARDFILE SKIP 1 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LRTRIM MISSING FIELD VALUES ARE NULL) LOCATION('ZONE_AGENTI.csv')) REJECT LIMIT UNLIMITED;

				INSERT INTO zone_agenti (
					id
					,id_zona
					,id_agent
					,start_date
					,end_date
					)
				SELECT id
					,id_zona
					,id_agent
					,TO_DATE(start_date, 'YYYY-MM-DD')
					,CASE 
						WHEN end_date = 'NULL'
							THEN NULL
						ELSE TO_DATE(end_date, 'YYYY-MM-DD')
						END
				FROM ext_za;

				DROP TABLE ext_za;

				-- ============================================================================
				-- ZONE_INTERVALE_PLATA
				-- ============================================================================
				CREATE TABLE ext_zip (
					id NUMBER(19)
					,id_zona NUMBER(19)
					,id_interval NUMBER(19)
					,start_date VARCHAR2(20)
					,end_date VARCHAR2(20)
					) ORGANIZATION EXTERNAL (TYPE ORACLE_LOADER DEFAULT DIRECTORY csv_dir ACCESS PARAMETERS(RECORDS DELIMITED BY NEWLINE CHARACTERSET UTF8 NOLOGFILE NOBADFILE NODISCARDFILE SKIP 1 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LRTRIM MISSING FIELD VALUES ARE NULL) LOCATION('ZONE_INTERVALE_PLATA.csv')) REJECT LIMIT UNLIMITED;

				INSERT INTO zone_intervale_plata (
					id
					,id_zona
					,id_interval
					,start_date
					,end_date
					)
				SELECT id
					,id_zona
					,id_interval
					,TO_DATE(start_date, 'YYYY-MM-DD')
					,CASE 
						WHEN end_date = 'NULL'
							THEN NULL
						ELSE TO_DATE(end_date, 'YYYY-MM-DD')
						END
				FROM ext_zip;

				DROP TABLE ext_zip;

				COMMIT;

				-- ============================================================================
				-- RULEAZA CA: sgbd_catalog IN PDB-UL "CATALOG"
				-- Catalog produse cu fragmentare verticala BEA
				-- ============================================================================
				CONNECT sgbd_catalog / oracle@ //localhost:1521/CATALOG

				-- ----------------------------------------------------------------------------
				-- Pas 3.1: DDL - 4 lookup + ITEMS_CORE/ITEMS_EXTRA (fragmente V)
				-- ----------------------------------------------------------------------------
				-- ============================================================================
				-- BRANDS
				-- ============================================================================
				CREATE TABLE brands (
					id NUMBER(19)
					,code VARCHAR2(3) NOT NULL
					,brand VARCHAR2(50)
					,description VARCHAR2(300)
					,CONSTRAINT pk_brands PRIMARY KEY (id)
					,CONSTRAINT uk_brands_code UNIQUE (code)
					);

				-- ============================================================================
				-- ITEMS_CATEGORY
				-- ============================================================================
				CREATE TABLE items_category (
					id NUMBER(19)
					,code VARCHAR2(2) NOT NULL
					,category VARCHAR2(50) NOT NULL
					,name VARCHAR2(50) NOT NULL
					,CONSTRAINT pk_items_category PRIMARY KEY (id)
					,CONSTRAINT uk_cat_code UNIQUE (code)
					);

				-- ============================================================================
				-- ITEMS_TYPE
				-- ============================================================================
				CREATE TABLE items_type (
					id NUMBER(19)
					,code VARCHAR2(4)
					,item_type VARCHAR2(200)
					,description VARCHAR2(600)
					,CONSTRAINT pk_items_type PRIMARY KEY (id)
					,CONSTRAINT uk_type_code UNIQUE (code)
					);

				-- ============================================================================
				-- ITEMS_SEASONS
				-- ============================================================================
				CREATE TABLE items_seasons (
					id NUMBER(19)
					,code VARCHAR2(120)
					,description VARCHAR2(40)
					,season_year VARCHAR2(8)
					,active NUMBER(10)
					,CONSTRAINT pk_items_seasons PRIMARY KEY (id)
					,CONSTRAINT uk_seasons_code UNIQUE (code)
					,CONSTRAINT ck_seasons_active CHECK (
						active IN (
							0
							,1
							)
						)
					);

				-- ============================================================================
				-- ITEMS_CORE: fragmentul vertical 1 = identitate + clasificare
				-- (item_code, item_name, FK-uri spre cele 4 lookups, flag active)
				-- ============================================================================
				CREATE TABLE items_core (
					id NUMBER(19)
					,item_code VARCHAR2(50) NOT NULL
					,item_name VARCHAR2(350) NOT NULL
					,brand_id NUMBER(19)
					,season_id NUMBER(19)
					,item_type_id NUMBER(19)
					,category_id NUMBER(19)
					,active NUMBER
					,CONSTRAINT pk_items_core PRIMARY KEY (id)
					,CONSTRAINT uk_items_code UNIQUE (item_code)
					,CONSTRAINT fk_items_brand FOREIGN KEY (brand_id) REFERENCES brands(id)
					,CONSTRAINT fk_items_season FOREIGN KEY (season_id) REFERENCES items_seasons(id)
					,CONSTRAINT fk_items_type FOREIGN KEY (item_type_id) REFERENCES items_type(id)
					,CONSTRAINT fk_items_category FOREIGN KEY (category_id) REFERENCES items_category(id)
					);

				-- ============================================================================
				-- ITEMS_EXTRA: fragmentul vertical 2 = atribute comerciale + fizice
				-- 1:1 cu ITEMS_CORE prin id (FK + ON DELETE CASCADE)
				-- ============================================================================
				CREATE TABLE items_extra (
					id NUMBER(19)
					,item_description VARCHAR2(1000)
					,vat BINARY_DOUBLE
					,last_cost_price NUMBER(9, 2)
					,main_barcode VARCHAR2(20)
					,supplier_code VARCHAR2(60)
					,weight NUMBER(9, 2)
					,um VARCHAR2(10)
					,CONSTRAINT pk_items_extra PRIMARY KEY (id)
					,CONSTRAINT fk_items_extra_core FOREIGN KEY (id) REFERENCES items_core(id) ON DELETE CASCADE
					);

				-- ----------------------------------------------------------------------------
				-- Pas 3.2: Load ITEMS split CORE/EXTRA
				-- ----------------------------------------------------------------------------
				-- ============================================================================
				-- BRANDS
				-- ============================================================================
				CREATE TABLE ext_brands (
					id NUMBER(19)
					,code VARCHAR2(3)
					,brand VARCHAR2(50)
					,description VARCHAR2(300)
					) ORGANIZATION EXTERNAL (TYPE ORACLE_LOADER DEFAULT DIRECTORY csv_dir ACCESS PARAMETERS(RECORDS DELIMITED BY NEWLINE CHARACTERSET UTF8 NOLOGFILE NOBADFILE NODISCARDFILE SKIP 1 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LRTRIM MISSING FIELD VALUES ARE NULL) LOCATION('BRANDS.csv')) REJECT LIMIT UNLIMITED;

				INSERT INTO brands (
					id
					,code
					,brand
					,description
					)
				SELECT id
					,code
					,NULLIF(brand, 'NULL')
					,NULLIF(description, 'NULL')
				FROM ext_brands;

				DROP TABLE ext_brands;

				-- ============================================================================
				-- ITEMS_CATEGORY
				-- ============================================================================
				CREATE TABLE ext_items_cat (
					id NUMBER(19)
					,code VARCHAR2(2)
					,category VARCHAR2(50)
					,name VARCHAR2(50)
					) ORGANIZATION EXTERNAL (TYPE ORACLE_LOADER DEFAULT DIRECTORY csv_dir ACCESS PARAMETERS(RECORDS DELIMITED BY NEWLINE CHARACTERSET UTF8 NOLOGFILE NOBADFILE NODISCARDFILE SKIP 1 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LRTRIM MISSING FIELD VALUES ARE NULL) LOCATION('ITEMS_CATEGORY.csv')) REJECT LIMIT UNLIMITED;

				INSERT INTO items_category
				SELECT *
				FROM ext_items_cat;

				DROP TABLE ext_items_cat;

				-- ============================================================================
				-- ITEMS_TYPE
				-- ============================================================================
				CREATE TABLE ext_items_type (
					id NUMBER(19)
					,code VARCHAR2(4)
					,item_type VARCHAR2(200)
					,description VARCHAR2(600)
					) ORGANIZATION EXTERNAL (TYPE ORACLE_LOADER DEFAULT DIRECTORY csv_dir ACCESS PARAMETERS(RECORDS DELIMITED BY NEWLINE CHARACTERSET UTF8 NOLOGFILE NOBADFILE NODISCARDFILE SKIP 1 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LRTRIM MISSING FIELD VALUES ARE NULL) LOCATION('ITEMS_TYPE.csv')) REJECT LIMIT UNLIMITED;

				INSERT INTO items_type (
					id
					,code
					,item_type
					,description
					)
				SELECT id
					,code
					,item_type
					,NULLIF(description, 'NULL')
				FROM ext_items_type;

				DROP TABLE ext_items_type;

				-- ============================================================================
				-- ITEMS_SEASONS
				-- ============================================================================
				CREATE TABLE ext_items_seasons (
					id NUMBER(19)
					,code VARCHAR2(120)
					,description VARCHAR2(40)
					,season_year VARCHAR2(8)
					,active NUMBER(10)
					) ORGANIZATION EXTERNAL (TYPE ORACLE_LOADER DEFAULT DIRECTORY csv_dir ACCESS PARAMETERS(RECORDS DELIMITED BY NEWLINE CHARACTERSET UTF8 NOLOGFILE NOBADFILE NODISCARDFILE SKIP 1 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LRTRIM MISSING FIELD VALUES ARE NULL) LOCATION('ITEMS_SEASONS.csv')) REJECT LIMIT UNLIMITED;

				INSERT INTO items_seasons (
					id
					,code
					,description
					,season_year
					,active
					)
				SELECT id
					,code
					,description
					,season_year
					,active
				FROM ext_items_seasons;

				DROP TABLE ext_items_seasons;

				-- ============================================================================
				-- ITEMS (CORE + EXTRA)
				-- ============================================================================
				CREATE TABLE ext_items (
					id NUMBER(19)
					,item_code VARCHAR2(50)
					,item_name VARCHAR2(350)
					,item_description VARCHAR2(1000)
					,brand_id VARCHAR2(20)
					,season_id VARCHAR2(20)
					,item_type_id VARCHAR2(20)
					,category_id VARCHAR2(20)
					,vat VARCHAR2(40)
					,last_cost_price VARCHAR2(40)
					,main_barcode VARCHAR2(20)
					,supplier_code VARCHAR2(60)
					,weight VARCHAR2(40)
					,um VARCHAR2(10)
					,active VARCHAR2(10)
					) ORGANIZATION EXTERNAL (TYPE ORACLE_LOADER DEFAULT DIRECTORY csv_dir ACCESS PARAMETERS(RECORDS DELIMITED BY NEWLINE CHARACTERSET UTF8 NOLOGFILE NOBADFILE NODISCARDFILE SKIP 1 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LRTRIM MISSING FIELD VALUES ARE NULL) LOCATION('ITEMS.csv')) REJECT LIMIT UNLIMITED;

				-- CORE (identitate + clasificare)
				INSERT INTO items_core (
					id
					,item_code
					,item_name
					,brand_id
					,season_id
					,item_type_id
					,category_id
					,active
					)
				SELECT id
					,item_code
					,item_name
					,CAST(NULLIF(brand_id, 'NULL') AS NUMBER(19))
					,CAST(NULLIF(season_id, 'NULL') AS NUMBER(19))
					,CAST(NULLIF(item_type_id, 'NULL') AS NUMBER(19))
					,CAST(NULLIF(category_id, 'NULL') AS NUMBER(19))
					,CAST(NULLIF(active, 'NULL') AS NUMBER)
				FROM ext_items;

				-- EXTRA (comercial + fizic)
				INSERT INTO items_extra (
					id
					,item_description
					,vat
					,last_cost_price
					,main_barcode
					,supplier_code
					,weight
					,um
					)
				SELECT id
					,NULLIF(item_description, 'NULL')
					,CAST(NULLIF(vat, 'NULL') AS BINARY_DOUBLE)
					,CAST(NULLIF(last_cost_price, 'NULL') AS NUMBER(9, 2))
					,NULLIF(main_barcode, 'NULL')
					,NULLIF(supplier_code, 'NULL')
					,CAST(NULLIF(weight, 'NULL') AS NUMBER(9, 2))
					,NULLIF(um, 'NULL')
				FROM ext_items;

				DROP TABLE ext_items;

				COMMIT;

				-- ============================================================================
				-- RULEAZA CA: sgbd_vanzari IN PDB-UL "VANZARI"
				-- Fact tables cu fragmentare orizontala RO/EXT
				-- ============================================================================
				CONNECT sgbd_vanzari / oracle@ //localhost:1521/VANZARI

				-- ----------------------------------------------------------------------------
				-- Pas 4.1: DDL - 4 fragmente fizice (FISE_CLIENTI_RO/EXT + LINII_DOC_RO/EXT)
				-- ----------------------------------------------------------------------------
				-- ============================================================================
				-- FISE_CLIENTI_RO: fragment H primar 1 (moneda = 'RON')
				-- ============================================================================
				CREATE TABLE fise_clienti_ro (
					id NUMBER(19)
					,nr_document VARCHAR2(30) NOT NULL
					,nr_doc_initial VARCHAR2(30)
					,tip_doc CHAR(1) NOT NULL
					,doc_type_xrp CHAR(3) NOT NULL
					,data_doc_efectiva DATE NOT NULL
					,data_scad DATE
					,semn NUMBER(2) NOT NULL
					,moneda VARCHAR2(10) NOT NULL
					,amount_doc NUMBER(17, 2) NOT NULL
					,amount_doc_ron NUMBER(17, 2) NOT NULL
					,plata_prin VARCHAR2(20)
					,cod_client VARCHAR2(60) NOT NULL
					,denumire_client VARCHAR2(200) NOT NULL
					,clasa_client VARCHAR2(20) NOT NULL
					,CONSTRAINT pk_fise_ro PRIMARY KEY (id)
					,CONSTRAINT uk_fise_ro_doc UNIQUE (
						nr_document
						,doc_type_xrp
						)
					,CONSTRAINT ck_fise_ro_mon CHECK (moneda = 'RON')
					,CONSTRAINT ck_fise_ro_tipdoc CHECK (
						tip_doc IN (
							'F'
							,'I'
							)
						)
					,CONSTRAINT ck_fise_ro_xrp CHECK (
						doc_type_xrp IN (
							'INV'
							,'PMT'
							,'CRM'
							,'PPM'
							,'REF'
							,'RPM'
							,'DRM'
							,'VRF'
							)
						)
					,CONSTRAINT ck_fise_ro_semn CHECK (
						semn IN (
							- 1
							,1
							)
						)
					);

				-- ============================================================================
				-- FISE_CLIENTI_EXT: fragment H primar 2 (moneda <> 'RON' (EUR / CZK / USD))
				-- ============================================================================
				CREATE TABLE fise_clienti_ext (
					id NUMBER(19)
					,nr_document VARCHAR2(30) NOT NULL
					,nr_doc_initial VARCHAR2(30)
					,tip_doc CHAR(1) NOT NULL
					,doc_type_xrp CHAR(3) NOT NULL
					,data_doc_efectiva DATE NOT NULL
					,data_scad DATE
					,semn NUMBER(2) NOT NULL
					,moneda VARCHAR2(10) NOT NULL
					,amount_doc NUMBER(17, 2) NOT NULL
					,amount_doc_ron NUMBER(17, 2) NOT NULL
					,plata_prin VARCHAR2(20)
					,cod_client VARCHAR2(60) NOT NULL
					,denumire_client VARCHAR2(200) NOT NULL
					,clasa_client VARCHAR2(20) NOT NULL
					,CONSTRAINT pk_fise_ext PRIMARY KEY (id)
					,CONSTRAINT uk_fise_ext_doc UNIQUE (
						nr_document
						,doc_type_xrp
						)
					,CONSTRAINT ck_fise_ext_mon CHECK (moneda <> 'RON')
					,CONSTRAINT ck_fise_ext_tipdoc CHECK (
						tip_doc IN (
							'F'
							,'I'
							)
						)
					,CONSTRAINT ck_fise_ext_xrp CHECK (
						doc_type_xrp IN (
							'INV'
							,'PMT'
							,'CRM'
							,'PPM'
							,'REF'
							,'RPM'
							,'DRM'
							,'VRF'
							)
						)
					,CONSTRAINT ck_fise_ext_semn CHECK (
						semn IN (
							- 1
							,1
							)
						)
					);

				-- ============================================================================
				-- LINII_DOC_RO: fragment H derivat 1
				-- (linii care apartin de documente din FISE_CLIENTI_RO)
				-- ============================================================================
				CREATE TABLE linii_doc_ro (
					id NUMBER(19)
					,doc_type_xrp CHAR(3) NOT NULL
					,nr_document VARCHAR2(30) NOT NULL
					,item_code VARCHAR2(50) NOT NULL
					,item_qty NUMBER(13, 2)
					,xrp_doc_valoare_fara_tva NUMBER(9, 2)
					,xrp_doc_tva NUMBER(9, 2)
					,xrp_doc_procent_tva NUMBER(9, 2)
					,xrp_doc_valoare_totala NUMBER(9, 2)
					,xrp_linie_is_with_vat VARCHAR2(40)
					,xrp_linie_valoare_fara_tva NUMBER(9, 2)
					,xrp_linie_tva NUMBER(9, 2)
					,xrp_linie_proc_tva NUMBER(9, 2)
					,CONSTRAINT pk_linii_doc_ro PRIMARY KEY (id)
					,CONSTRAINT fk_lin_ro_fise FOREIGN KEY (
						nr_document
						,doc_type_xrp
						) REFERENCES fise_clienti_ro(nr_document, doc_type_xrp)
						ON DELETE CASCADE
					);

				-- ============================================================================
				-- LINII_DOC_EXT: fragment H derivat 2
				-- (linii care apartin de documente din FISE_CLIENTI_EXT)
				-- ============================================================================
				CREATE TABLE linii_doc_ext (
					id NUMBER(19)
					,doc_type_xrp CHAR(3) NOT NULL
					,nr_document VARCHAR2(30) NOT NULL
					,item_code VARCHAR2(50) NOT NULL
					,item_qty NUMBER(13, 2)
					,xrp_doc_valoare_fara_tva NUMBER(9, 2)
					,xrp_doc_tva NUMBER(9, 2)
					,xrp_doc_procent_tva NUMBER(9, 2)
					,xrp_doc_valoare_totala NUMBER(9, 2)
					,xrp_linie_is_with_vat VARCHAR2(40)
					,xrp_linie_valoare_fara_tva NUMBER(9, 2)
					,xrp_linie_tva NUMBER(9, 2)
					,xrp_linie_proc_tva NUMBER(9, 2)
					,CONSTRAINT pk_linii_doc_ext PRIMARY KEY (id)
					,CONSTRAINT fk_lin_ext_fise FOREIGN KEY (
						nr_document
						,doc_type_xrp
						) REFERENCES fise_clienti_ext(nr_document, doc_type_xrp)
						ON DELETE CASCADE
					);

				-- ----------------------------------------------------------------------------
				-- Pas 4.2: Load docs + linii cu split pe Moneda
				-- ----------------------------------------------------------------------------
				CREATE TABLE ext_fise_all (
					id NUMBER(19)
					,nr_document VARCHAR2(30)
					,nr_doc_initial VARCHAR2(30)
					,tip_doc CHAR(1)
					,doc_type_xrp CHAR(3)
					,data_doc_efectiva VARCHAR2(20)
					,data_scad VARCHAR2(20)
					,semn NUMBER(2)
					,moneda VARCHAR2(10)
					,amount_doc NUMBER(17, 2)
					,amount_doc_ron NUMBER(17, 2)
					,plata_prin VARCHAR2(20)
					,cod_client VARCHAR2(60)
					,denumire_client VARCHAR2(200)
					,clasa_client VARCHAR2(20)
					) ORGANIZATION EXTERNAL (TYPE ORACLE_LOADER DEFAULT DIRECTORY csv_dir ACCESS PARAMETERS(RECORDS DELIMITED BY NEWLINE CHARACTERSET UTF8 NOLOGFILE NOBADFILE NODISCARDFILE SKIP 1 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LRTRIM MISSING FIELD VALUES ARE NULL) LOCATION('DOCS_HEADERS.csv')) REJECT LIMIT UNLIMITED;

				-- ============================================================================
				-- FISE_CLIENTI_RO (fragment H primar 1: moneda = 'RON')
				-- ============================================================================
				INSERT INTO fise_clienti_ro (
					id
					,nr_document
					,nr_doc_initial
					,tip_doc
					,doc_type_xrp
					,data_doc_efectiva
					,data_scad
					,semn
					,moneda
					,amount_doc
					,amount_doc_ron
					,plata_prin
					,cod_client
					,denumire_client
					,clasa_client
					)
				SELECT id
					,nr_document
					,NULLIF(nr_doc_initial, 'NULL')
					,tip_doc
					,doc_type_xrp
					,TO_DATE(data_doc_efectiva, 'YYYY-MM-DD')
					,CASE 
						WHEN data_scad = 'NULL'
							THEN NULL
						ELSE TO_DATE(data_scad, 'YYYY-MM-DD')
						END
					,semn
					,moneda
					,amount_doc
					,amount_doc_ron
					,NULLIF(plata_prin, 'NULL')
					,cod_client
					,denumire_client
					,clasa_client
				FROM ext_fise_all
				WHERE moneda = 'RON';

				-- ============================================================================
				-- FISE_CLIENTI_EXT (fragment H primar 2: moneda <> 'RON')
				-- ============================================================================
				INSERT INTO fise_clienti_ext (
					id
					,nr_document
					,nr_doc_initial
					,tip_doc
					,doc_type_xrp
					,data_doc_efectiva
					,data_scad
					,semn
					,moneda
					,amount_doc
					,amount_doc_ron
					,plata_prin
					,cod_client
					,denumire_client
					,clasa_client
					)
				SELECT id
					,nr_document
					,NULLIF(nr_doc_initial, 'NULL')
					,tip_doc
					,doc_type_xrp
					,TO_DATE(data_doc_efectiva, 'YYYY-MM-DD')
					,CASE 
						WHEN data_scad = 'NULL'
							THEN NULL
						ELSE TO_DATE(data_scad, 'YYYY-MM-DD')
						END
					,semn
					,moneda
					,amount_doc
					,amount_doc_ron
					,NULLIF(plata_prin, 'NULL')
					,cod_client
					,denumire_client
					,clasa_client
				FROM ext_fise_all
				WHERE moneda <> 'RON';

				DROP TABLE ext_fise_all;

				-- ============================================================================
				CREATE TABLE ext_linii_all (
					id NUMBER(19)
					,doc_type_xrp CHAR(3)
					,nr_document VARCHAR2(30)
					,item_code VARCHAR2(50)
					,item_qty NUMBER(13, 2)
					,xrp_doc_valoare_fara_tva NUMBER(9, 2)
					,xrp_doc_tva NUMBER(9, 2)
					,xrp_doc_procent_tva NUMBER(9, 2)
					,xrp_doc_valoare_totala NUMBER(9, 2)
					,xrp_linie_is_with_vat VARCHAR2(40)
					,xrp_linie_valoare_fara_tva NUMBER(9, 2)
					,xrp_linie_tva NUMBER(9, 2)
					,xrp_linie_proc_tva NUMBER(9, 2)
					) ORGANIZATION EXTERNAL (TYPE ORACLE_LOADER DEFAULT DIRECTORY csv_dir ACCESS PARAMETERS(RECORDS DELIMITED BY NEWLINE CHARACTERSET UTF8 NOLOGFILE NOBADFILE NODISCARDFILE SKIP 1 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LRTRIM MISSING FIELD VALUES ARE NULL) LOCATION('DOCS_LINES.csv')) REJECT LIMIT UNLIMITED;

				-- ============================================================================
				-- LINII_DOC_RO (linii al caror header e in fise_clienti_ro)
				-- ============================================================================
				INSERT INTO linii_doc_ro
				SELECT l.*
				FROM ext_linii_all l
				WHERE EXISTS (
						SELECT 1
						FROM fise_clienti_ro f
						WHERE f.nr_document = l.nr_document
							AND f.doc_type_xrp = l.doc_type_xrp
						);

				-- ============================================================================
				-- LINII_DOC_EXT (linii al caror header e in fise_clienti_ext)
				-- ============================================================================
				INSERT INTO linii_doc_ext
				SELECT l.*
				FROM ext_linii_all l
				WHERE EXISTS (
						SELECT 1
						FROM fise_clienti_ext f
						WHERE f.nr_document = l.nr_document
							AND f.doc_type_xrp = l.doc_type_xrp
						);

				DROP TABLE ext_linii_all;

				COMMIT;

				EXIT
				
				
				
-- =============================================================================
-- Demo_Schema.sql - Layerul de transparenta + replicare + optimizare
-- =============================================================================
-- Poate fi rulat de oricate ori pe o BD care are deja tabelele populate
--
-- Reminder:
--   MV-urile + DB links + FK + indecsi + job NU au CREATE OR REPLACE,
--   de aceea trebuie drop-uite explicit inainte de re-creere
-- =============================================================================
--======================================
-- User:  sgbd_vanzari
-- PDB:   VANZARI
-- Parola: oracle (role Normal)
--======================================
-- Drop 8 indecsi
BEGIN
	EXECUTE IMMEDIATE 'DROP INDEX idx_fise_ro_data';

	EXCEPTION WHEN OTHERS THEN NULL;
END;

BEGIN
	EXECUTE IMMEDIATE 'DROP INDEX idx_fise_ro_codcli';

	EXCEPTION WHEN OTHERS THEN NULL;
END;

BEGIN
	EXECUTE IMMEDIATE 'DROP INDEX idx_fise_ro_tip';

	EXCEPTION WHEN OTHERS THEN NULL;
END;

BEGIN
	EXECUTE IMMEDIATE 'DROP INDEX idx_fise_ext_data';

	EXCEPTION WHEN OTHERS THEN NULL;
END;

BEGIN
	EXECUTE IMMEDIATE 'DROP INDEX idx_fise_ext_codcli';

	EXCEPTION WHEN OTHERS THEN NULL;
END;

BEGIN
	EXECUTE IMMEDIATE 'DROP INDEX idx_fise_ext_tip';

	EXCEPTION WHEN OTHERS THEN NULL;
END;

BEGIN
	EXECUTE IMMEDIATE 'DROP INDEX idx_lin_ro_item';

	EXCEPTION WHEN OTHERS THEN NULL;
END;

BEGIN
	EXECUTE IMMEDIATE 'DROP INDEX idx_lin_ext_item';

	EXCEPTION WHEN OTHERS THEN NULL;
END;

-- Drop job DBMS_SCHEDULER
BEGIN
	DBMS_SCHEDULER.DROP_JOB(job_name => 'JOB_REFRESH_MVS', FORCE => TRUE);

	EXCEPTION WHEN OTHERS THEN NULL;
END;

-- Drop 4 FK cross-PDB
BEGIN
	EXECUTE IMMEDIATE 'ALTER TABLE fise_clienti_ro  DROP CONSTRAINT fk_fise_ro_client';

	EXCEPTION WHEN OTHERS THEN NULL;
END;

BEGIN
	EXECUTE IMMEDIATE 'ALTER TABLE fise_clienti_ext DROP CONSTRAINT fk_fise_ext_client';

	EXCEPTION WHEN OTHERS THEN NULL;
END;

BEGIN
	EXECUTE IMMEDIATE 'ALTER TABLE linii_doc_ro     DROP CONSTRAINT fk_lin_ro_item';

	EXCEPTION WHEN OTHERS THEN NULL;
END;

BEGIN
	EXECUTE IMMEDIATE 'ALTER TABLE linii_doc_ext    DROP CONSTRAINT fk_lin_ext_item';

	EXCEPTION WHEN OTHERS THEN NULL;
END;

-- Drop 7 MV-uri replicate
BEGIN
	EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW mv_clienti';

	EXCEPTION WHEN OTHERS THEN NULL;
END;

BEGIN
	EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW mv_zone';

	EXCEPTION WHEN OTHERS THEN NULL;
END;

BEGIN
	EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW mv_items_core';

	EXCEPTION WHEN OTHERS THEN NULL;
END;

BEGIN
	EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW mv_brands';

	EXCEPTION WHEN OTHERS THEN NULL;
END;

BEGIN
	EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW mv_items_category';

	EXCEPTION WHEN OTHERS THEN NULL;
END;

BEGIN
	EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW mv_items_type';

	EXCEPTION WHEN OTHERS THEN NULL;
END;

BEGIN
	EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW mv_items_seasons';

	EXCEPTION WHEN OTHERS THEN NULL;
END;

-- Drop 2 DB links
BEGIN
	EXECUTE IMMEDIATE 'DROP DATABASE LINK lnk_distributie';

	EXCEPTION WHEN OTHERS THEN NULL;
END;

BEGIN
	EXECUTE IMMEDIATE 'DROP DATABASE LINK lnk_catalog';

	EXCEPTION WHEN OTHERS THEN NULL;
END;

--======================================
-- User:  sys
-- PDB:   XE
-- Parola: ModbdSecret123 (role SYSDBA)
--======================================
-- Drop MV LOGs
ALTER SESSION

SET CONTAINER = DISTRIBUTIE;

ALTER SESSION

SET CURRENT_SCHEMA = sgbd_distributie;

BEGIN
	EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW LOG ON clienti';

	EXCEPTION WHEN OTHERS THEN NULL;
END;

BEGIN
	EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW LOG ON zone';

	EXCEPTION WHEN OTHERS THEN NULL;
END;

ALTER SESSION

SET CONTAINER = CATALOG;

ALTER SESSION

SET CURRENT_SCHEMA = sgbd_catalog;

BEGIN
	EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW LOG ON items_core';

	EXCEPTION WHEN OTHERS THEN NULL;
END;

BEGIN
	EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW LOG ON brands';

	EXCEPTION WHEN OTHERS THEN NULL;
END;

BEGIN
	EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW LOG ON items_category';

	EXCEPTION WHEN OTHERS THEN NULL;
END;

BEGIN
	EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW LOG ON items_type';

	EXCEPTION WHEN OTHERS THEN NULL;
END;

BEGIN
	EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW LOG ON items_seasons';

	EXCEPTION WHEN OTHERS THEN NULL;
END;

-- ----------------------------------------------------------------------------
-- Re-creare MV LOGs (WITH PRIMARY KEY, ROWID, SEQUENCE pentru REFRESH FAST)
-- ----------------------------------------------------------------------------
-- ============================================================================
-- DISTRIBUTIE: MV logs pe tabelele master care vor fi replicate in VANZARI
-- ============================================================================
ALTER SESSION

SET CONTAINER = DISTRIBUTIE;

ALTER SESSION

SET CURRENT_SCHEMA = sgbd_distributie;

CREATE MATERIALIZED VIEW LOG ON clienti
	WITH PRIMARY KEY
		,ROWID
		,SEQUENCE INCLUDING NEW
VALUES;

CREATE MATERIALIZED VIEW LOG ON zone
	WITH PRIMARY KEY
		,ROWID
		,SEQUENCE INCLUDING NEW
VALUES;

-- ============================================================================
-- CATALOG: MV logs pe tabelele master + items_core (fragment vertical)
-- ============================================================================
ALTER SESSION

SET CONTAINER = CATALOG;

ALTER SESSION

SET CURRENT_SCHEMA = sgbd_catalog;

CREATE MATERIALIZED VIEW LOG ON items_core
	WITH PRIMARY KEY
		,ROWID
		,SEQUENCE INCLUDING NEW
VALUES;

CREATE MATERIALIZED VIEW LOG ON brands
	WITH PRIMARY KEY
		,ROWID
		,SEQUENCE INCLUDING NEW
VALUES;

CREATE MATERIALIZED VIEW LOG ON items_category
	WITH PRIMARY KEY
		,ROWID
		,SEQUENCE INCLUDING NEW
VALUES;

CREATE MATERIALIZED VIEW LOG ON items_type
	WITH PRIMARY KEY
		,ROWID
		,SEQUENCE INCLUDING NEW
VALUES;

CREATE MATERIALIZED VIEW LOG ON items_seasons
	WITH PRIMARY KEY
		,ROWID
		,SEQUENCE INCLUDING NEW
VALUES;

--======================================
-- User:  sgbd_catalog
-- PDB:   CATALOG
-- Parola: oracle (role Normal)
--======================================
-- ============================================================================
-- V_ITEMS: view de transparenta verticala (JOIN intre CORE si EXTRA dupa id)
-- Expune toate cele 15 coloane originale ale ITEMS
-- ============================================================================
CREATE
	OR REPLACE VIEW v_items (
	id
	,item_code
	,item_name
	,item_description
	,brand_id
	,season_id
	,item_type_id
	,category_id
	,vat
	,last_cost_price
	,main_barcode
	,supplier_code
	,weight
	,um
	,active
	) AS

SELECT c.id
	,c.item_code
	,c.item_name
	,e.item_description
	,c.brand_id
	,c.season_id
	,c.item_type_id
	,c.category_id
	,e.vat
	,e.last_cost_price
	,e.main_barcode
	,e.supplier_code
	,e.weight
	,e.um
	,c.active
FROM items_core c
JOIN items_extra e ON e.id = c.id;

-- ============================================================================
-- Trigger INSTEAD OF INSERT pe V_ITEMS
-- Sparge insertul in 2: o linie in CORE + o linie in EXTRA (acelasi id)
-- ============================================================================
CREATE
	OR REPLACE TRIGGER trg_v_items_ins INSTEAD OF

INSERT ON v_items
FOR EACH ROW

BEGIN
	INSERT INTO items_core (
		id
		,item_code
		,item_name
		,brand_id
		,season_id
		,item_type_id
		,category_id
		,active
		)
	VALUES (
		:NEW.id
		,:NEW.item_code
		,:NEW.item_name
		,:NEW.brand_id
		,:NEW.season_id
		,:NEW.item_type_id
		,:NEW.category_id
		,:NEW.active
		);

	INSERT INTO items_extra (
		id
		,item_description
		,vat
		,last_cost_price
		,main_barcode
		,supplier_code
		,weight
		,um
		)
	VALUES (
		:NEW.id
		,:NEW.item_description
		,:NEW.vat
		,:NEW.last_cost_price
		,:NEW.main_barcode
		,:NEW.supplier_code
		,:NEW.weight
		,:NEW.um
		);
END;

-- ============================================================================
-- Trigger INSTEAD OF UPDATE pe V_ITEMS
-- Update simultan in ambele fragmente
-- ============================================================================
CREATE
	OR REPLACE TRIGGER trg_v_items_upd INSTEAD OF

UPDATE ON v_items
FOR EACH ROW

BEGIN
	UPDATE items_core
	SET item_code = :NEW.item_code
		,item_name = :NEW.item_name
		,brand_id = :NEW.brand_id
		,season_id = :NEW.season_id
		,item_type_id = :NEW.item_type_id
		,category_id = :NEW.category_id
		,active = :NEW.active
	WHERE id = :OLD.id;

	UPDATE items_extra
	SET item_description = :NEW.item_description
		,vat = :NEW.vat
		,last_cost_price = :NEW.last_cost_price
		,main_barcode = :NEW.main_barcode
		,supplier_code = :NEW.supplier_code
		,weight = :NEW.weight
		,um = :NEW.um
	WHERE id = :OLD.id;
END;

-- ============================================================================
-- Trigger INSTEAD OF DELETE pe V_ITEMS
-- DELETE pe items_core => ON DELETE CASCADE sterge automat items_extra
-- ============================================================================
CREATE
	OR REPLACE TRIGGER trg_v_items_del INSTEAD OF

DELETE ON v_items
FOR EACH ROW

BEGIN
	DELETE
	FROM items_core
	WHERE id = :OLD.id;
END;

--======================================
-- User:  sgbd_vanzari
-- PDB:   VANZARI
-- Parola: oracle (role Normal)
--======================================
-- ============================================================================
-- View V_FISE_CLIENTI: union all peste cele 2 fragmente orizontale (RO + EXT)
-- ============================================================================
CREATE
	OR REPLACE VIEW v_fise_clienti (
	id
	,nr_document
	,nr_doc_initial
	,tip_doc
	,doc_type_xrp
	,data_doc_efectiva
	,data_scad
	,semn
	,moneda
	,amount_doc
	,amount_doc_ron
	,plata_prin
	,cod_client
	,denumire_client
	,clasa_client
	) AS

SELECT id
	,nr_document
	,nr_doc_initial
	,tip_doc
	,doc_type_xrp
	,data_doc_efectiva
	,data_scad
	,semn
	,moneda
	,amount_doc
	,amount_doc_ron
	,plata_prin
	,cod_client
	,denumire_client
	,clasa_client
FROM fise_clienti_ro

UNION ALL

SELECT id
	,nr_document
	,nr_doc_initial
	,tip_doc
	,doc_type_xrp
	,data_doc_efectiva
	,data_scad
	,semn
	,moneda
	,amount_doc
	,amount_doc_ron
	,plata_prin
	,cod_client
	,denumire_client
	,clasa_client
FROM fise_clienti_ext;

-- ============================================================================
-- View V_LINII_DOC: union all peste linii_doc_ro + linii_doc_ext
-- ============================================================================
CREATE
	OR REPLACE VIEW v_linii_doc (
	id
	,doc_type_xrp
	,nr_document
	,item_code
	,item_qty
	,xrp_doc_valoare_fara_tva
	,xrp_doc_tva
	,xrp_doc_procent_tva
	,xrp_doc_valoare_totala
	,xrp_linie_is_with_vat
	,xrp_linie_valoare_fara_tva
	,xrp_linie_tva
	,xrp_linie_proc_tva
	) AS

SELECT id
	,doc_type_xrp
	,nr_document
	,item_code
	,item_qty
	,xrp_doc_valoare_fara_tva
	,xrp_doc_tva
	,xrp_doc_procent_tva
	,xrp_doc_valoare_totala
	,xrp_linie_is_with_vat
	,xrp_linie_valoare_fara_tva
	,xrp_linie_tva
	,xrp_linie_proc_tva
FROM linii_doc_ro

UNION ALL

SELECT id
	,doc_type_xrp
	,nr_document
	,item_code
	,item_qty
	,xrp_doc_valoare_fara_tva
	,xrp_doc_tva
	,xrp_doc_procent_tva
	,xrp_doc_valoare_totala
	,xrp_linie_is_with_vat
	,xrp_linie_valoare_fara_tva
	,xrp_linie_tva
	,xrp_linie_proc_tva
FROM linii_doc_ext;

-- ============================================================================
-- Trigger INSTEAD OF INSERT pe V_FISE_CLIENTI
-- Routare dupa moneda
-- ============================================================================
CREATE
	OR REPLACE TRIGGER trg_v_fise_ins INSTEAD OF

INSERT ON v_fise_clienti
FOR EACH ROW

BEGIN
	IF :NEW.moneda = 'RON' THEN
		INSERT INTO fise_clienti_ro (
			id
			,nr_document
			,nr_doc_initial
			,tip_doc
			,doc_type_xrp
			,data_doc_efectiva
			,data_scad
			,semn
			,moneda
			,amount_doc
			,amount_doc_ron
			,plata_prin
			,cod_client
			,denumire_client
			,clasa_client
			)
		VALUES (
			:NEW.id
			,:NEW.nr_document
			,:NEW.nr_doc_initial
			,:NEW.tip_doc
			,:NEW.doc_type_xrp
			,:NEW.data_doc_efectiva
			,:NEW.data_scad
			,:NEW.semn
			,:NEW.moneda
			,:NEW.amount_doc
			,:NEW.amount_doc_ron
			,:NEW.plata_prin
			,:NEW.cod_client
			,:NEW.denumire_client
			,:NEW.clasa_client
			);
	ELSE
		INSERT INTO fise_clienti_ext (
			id
			,nr_document
			,nr_doc_initial
			,tip_doc
			,doc_type_xrp
			,data_doc_efectiva
			,data_scad
			,semn
			,moneda
			,amount_doc
			,amount_doc_ron
			,plata_prin
			,cod_client
			,denumire_client
			,clasa_client
			)
		VALUES (
			:NEW.id
			,:NEW.nr_document
			,:NEW.nr_doc_initial
			,:NEW.tip_doc
			,:NEW.doc_type_xrp
			,:NEW.data_doc_efectiva
			,:NEW.data_scad
			,:NEW.semn
			,:NEW.moneda
			,:NEW.amount_doc
			,:NEW.amount_doc_ron
			,:NEW.plata_prin
			,:NEW.cod_client
			,:NEW.denumire_client
			,:NEW.clasa_client
			);
END IF ;
END;
	-- ============================================================================
	-- Trigger INSTEAD OF UPDATE pe V_FISE_CLIENTI
	-- Patru cazuri:
	--   1. RON -> non-RON  : delete din ro, insert in ext (mutare cross-fragment)
	--   2. non-RON -> RON  : delete din ext, insert in ro (mutare cross-fragment)
	--   3. ramane RON      : update in fragmentul ro
	--   4. ramane non-RON  : update in fragmentul ext
	-- ============================================================================
	CREATE
		OR REPLACE TRIGGER trg_v_fise_upd INSTEAD OF

UPDATE ON v_fise_clienti
FOR EACH ROW

BEGIN
	-- Cazul 1: RON -> non-RON (mutare ro -> ext)
	IF :OLD.moneda = 'RON'
		AND :NEW.moneda <> 'RON' THEN
		DELETE
		FROM fise_clienti_ro
		WHERE id = :OLD.id;

	INSERT INTO fise_clienti_ext (
		id
		,nr_document
		,nr_doc_initial
		,tip_doc
		,doc_type_xrp
		,data_doc_efectiva
		,data_scad
		,semn
		,moneda
		,amount_doc
		,amount_doc_ron
		,plata_prin
		,cod_client
		,denumire_client
		,clasa_client
		)
	VALUES (
		:NEW.id
		,:NEW.nr_document
		,:NEW.nr_doc_initial
		,:NEW.tip_doc
		,:NEW.doc_type_xrp
		,:NEW.data_doc_efectiva
		,:NEW.data_scad
		,:NEW.semn
		,:NEW.moneda
		,:NEW.amount_doc
		,:NEW.amount_doc_ron
		,:NEW.plata_prin
		,:NEW.cod_client
		,:NEW.denumire_client
		,:NEW.clasa_client
		);

	-- Cazul 2: non-RON -> RON (mutare ext -> ro)
	ELSIF :OLD.moneda <> 'RON'
		AND :NEW.moneda = 'RON' THEN

	DELETE
	FROM fise_clienti_ext
	WHERE id = :OLD.id;

	INSERT INTO fise_clienti_ro (
		id
		,nr_document
		,nr_doc_initial
		,tip_doc
		,doc_type_xrp
		,data_doc_efectiva
		,data_scad
		,semn
		,moneda
		,amount_doc
		,amount_doc_ron
		,plata_prin
		,cod_client
		,denumire_client
		,clasa_client
		)
	VALUES (
		:NEW.id
		,:NEW.nr_document
		,:NEW.nr_doc_initial
		,:NEW.tip_doc
		,:NEW.doc_type_xrp
		,:NEW.data_doc_efectiva
		,:NEW.data_scad
		,:NEW.semn
		,:NEW.moneda
		,:NEW.amount_doc
		,:NEW.amount_doc_ron
		,:NEW.plata_prin
		,:NEW.cod_client
		,:NEW.denumire_client
		,:NEW.clasa_client
		);

	-- Cazul 3: ramane RON (update intra-fragment ro)
	ELSIF :OLD.moneda = 'RON' THEN

	UPDATE fise_clienti_ro
	SET nr_document = :NEW.nr_document
		,nr_doc_initial = :NEW.nr_doc_initial
		,tip_doc = :NEW.tip_doc
		,doc_type_xrp = :NEW.doc_type_xrp
		,data_doc_efectiva = :NEW.data_doc_efectiva
		,data_scad = :NEW.data_scad
		,semn = :NEW.semn
		,moneda = :NEW.moneda
		,amount_doc = :NEW.amount_doc
		,amount_doc_ron = :NEW.amount_doc_ron
		,plata_prin = :NEW.plata_prin
		,cod_client = :NEW.cod_client
		,denumire_client = :NEW.denumire_client
		,clasa_client = :NEW.clasa_client
	WHERE id = :OLD.id;
		-- Cazul 4: ramane non-RON (update intra-fragment ext)
		ELSE

	UPDATE fise_clienti_ext
	SET nr_document = :NEW.nr_document
		,nr_doc_initial = :NEW.nr_doc_initial
		,tip_doc = :NEW.tip_doc
		,doc_type_xrp = :NEW.doc_type_xrp
		,data_doc_efectiva = :NEW.data_doc_efectiva
		,data_scad = :NEW.data_scad
		,semn = :NEW.semn
		,moneda = :NEW.moneda
		,amount_doc = :NEW.amount_doc
		,amount_doc_ron = :NEW.amount_doc_ron
		,plata_prin = :NEW.plata_prin
		,cod_client = :NEW.cod_client
		,denumire_client = :NEW.denumire_client
		,clasa_client = :NEW.clasa_client
	WHERE id = :OLD.id;
END

IF ;END;
	-- ============================================================================
	-- Trigger INSTEAD OF DELETE pe V_FISE_CLIENTI
	-- ============================================================================
	CREATE
		OR REPLACE TRIGGER trg_v_fise_del INSTEAD OF

DELETE ON v_fise_clienti
FOR EACH ROW

BEGIN
	DELETE
	FROM fise_clienti_ro
	WHERE id = :OLD.id;

	DELETE
	FROM fise_clienti_ext
	WHERE id = :OLD.id;
END;

-- ============================================================================
-- Trigger INSTEAD OF INSERT pe V_LINII_DOC
-- Routare dupa fragmentul de FISE al documentului parinte
-- ============================================================================
CREATE
	OR REPLACE TRIGGER trg_v_lin_ins INSTEAD OF

INSERT ON v_linii_doc
FOR EACH ROW

DECLARE v_in_ro NUMBER;

BEGIN
	SELECT COUNT(*)
	INTO v_in_ro
	FROM fise_clienti_ro
	WHERE nr_document = :NEW.nr_document
		AND doc_type_xrp = :NEW.doc_type_xrp;

	IF v_in_ro > 0 THEN
		INSERT INTO linii_doc_ro (
			id
			,doc_type_xrp
			,nr_document
			,item_code
			,item_qty
			,xrp_doc_valoare_fara_tva
			,xrp_doc_tva
			,xrp_doc_procent_tva
			,xrp_doc_valoare_totala
			,xrp_linie_is_with_vat
			,xrp_linie_valoare_fara_tva
			,xrp_linie_tva
			,xrp_linie_proc_tva
			)
		VALUES (
			:NEW.id
			,:NEW.doc_type_xrp
			,:NEW.nr_document
			,:NEW.item_code
			,:NEW.item_qty
			,:NEW.xrp_doc_valoare_fara_tva
			,:NEW.xrp_doc_tva
			,:NEW.xrp_doc_procent_tva
			,:NEW.xrp_doc_valoare_totala
			,:NEW.xrp_linie_is_with_vat
			,:NEW.xrp_linie_valoare_fara_tva
			,:NEW.xrp_linie_tva
			,:NEW.xrp_linie_proc_tva
			);
	ELSE
		INSERT INTO linii_doc_ext (
			id
			,doc_type_xrp
			,nr_document
			,item_code
			,item_qty
			,xrp_doc_valoare_fara_tva
			,xrp_doc_tva
			,xrp_doc_procent_tva
			,xrp_doc_valoare_totala
			,xrp_linie_is_with_vat
			,xrp_linie_valoare_fara_tva
			,xrp_linie_tva
			,xrp_linie_proc_tva
			)
		VALUES (
			:NEW.id
			,:NEW.doc_type_xrp
			,:NEW.nr_document
			,:NEW.item_code
			,:NEW.item_qty
			,:NEW.xrp_doc_valoare_fara_tva
			,:NEW.xrp_doc_tva
			,:NEW.xrp_doc_procent_tva
			,:NEW.xrp_doc_valoare_totala
			,:NEW.xrp_linie_is_with_vat
			,:NEW.xrp_linie_valoare_fara_tva
			,:NEW.xrp_linie_tva
			,:NEW.xrp_linie_proc_tva
			);
END

IF ;END;
	-- ============================================================================
	-- Trigger INSTEAD OF DELETE pe V_LINII_DOC
	-- ============================================================================
	CREATE
		OR REPLACE TRIGGER trg_v_lin_del INSTEAD OF

DELETE ON v_linii_doc
FOR EACH ROW

BEGIN
	DELETE
	FROM linii_doc_ro
	WHERE id = :OLD.id;

	DELETE
	FROM linii_doc_ext
	WHERE id = :OLD.id;
END;

-- ----------------------------------------------------------------------------
-- DB Links private lnk_distributie + lnk_catalog
-- ----------------------------------------------------------------------------
-- ============================================================================
-- Link catre PDB-ul DISTRIBUTIE (CRM, master pentru clienti + zone)
-- ============================================================================
CREATE DATABASE LINK lnk_distributie CONNECT TO sgbd_distributie IDENTIFIED BY oracle USING 'localhost:1521DISTRIBUTIE';

-- ============================================================================
-- Link catre PDB-ul CATALOG (produse, master pentru items + lookups)
-- ============================================================================
CREATE DATABASE LINK lnk_catalog CONNECT TO sgbd_catalog IDENTIFIED BY oracle USING 'localhost:1521CATALOG';

-- ----------------------------------------------------------------------------
-- 7 MV-uri REFRESH FAST ON DEMAND + UK pentru a permite FK
-- ----------------------------------------------------------------------------
-- ============================================================================
-- MV_CLIENTI: replica DISTRIBUTIE.clienti
-- ============================================================================
CREATE MATERIALIZED VIEW mv_clienti BUILD IMMEDIATE REFRESH FAST ON DEMAND
	WITH PRIMARY KEY AS

SELECT *
FROM clienti@lnk_distributie;

ALTER TABLE mv_clienti ADD CONSTRAINT uk_mv_clienti_cod UNIQUE (cod_client);

-- ============================================================================
-- MV_ZONE: replica DISTRIBUTIE.zone
-- ============================================================================
CREATE MATERIALIZED VIEW mv_zone BUILD IMMEDIATE REFRESH FAST ON DEMAND
	WITH PRIMARY KEY AS

SELECT *
FROM zone@lnk_distributie;

-- ============================================================================
-- MV_ITEMS_CORE: replica CATALOG.items_core
-- ============================================================================
CREATE MATERIALIZED VIEW mv_items_core BUILD IMMEDIATE REFRESH FAST ON DEMAND
	WITH PRIMARY KEY AS

SELECT *
FROM items_core@lnk_catalog;

ALTER TABLE mv_items_core ADD CONSTRAINT uk_mv_items_code UNIQUE (item_code);

-- ============================================================================
-- MV_BRANDS: replica CATALOG.brands
-- ============================================================================
CREATE MATERIALIZED VIEW mv_brands BUILD IMMEDIATE REFRESH FAST ON DEMAND
	WITH PRIMARY KEY AS

SELECT *
FROM brands@lnk_catalog;

-- ============================================================================
-- MV_ITEMS_CATEGORY: replica CATALOG.items_category
-- ============================================================================
CREATE MATERIALIZED VIEW mv_items_category BUILD IMMEDIATE REFRESH FAST ON DEMAND
	WITH PRIMARY KEY AS

SELECT *
FROM items_category@lnk_catalog;

-- ============================================================================
-- MV_ITEMS_TYPE: replica CATALOG.items_type
-- ============================================================================
CREATE MATERIALIZED VIEW mv_items_type BUILD IMMEDIATE REFRESH FAST ON DEMAND
	WITH PRIMARY KEY AS

SELECT *
FROM items_type@lnk_catalog;

-- ============================================================================
-- MV_ITEMS_SEASONS: replica CATALOG.items_seasons
-- ============================================================================
CREATE MATERIALIZED VIEW mv_items_seasons BUILD IMMEDIATE REFRESH FAST ON DEMAND
	WITH PRIMARY KEY AS

SELECT *
FROM items_seasons@lnk_catalog;

-- ----------------------------------------------------------------------------
-- 4 FK cross-PDB: fise->mv_clienti (2), linii->mv_items_core (2)
-- ----------------------------------------------------------------------------
-- ============================================================================
-- Cleanup randurilor orfane (item_codes care nu exista in MV_ITEMS_CORE)
-- Acestea sunt date "murdare" din CSV-urile sursa care au fost gasite la rulare
-- ============================================================================
DELETE
FROM linii_doc_ro ldr
WHERE NOT EXISTS (
		SELECT 1
		FROM mv_items_core mic
		WHERE mic.item_code = ldr.item_code
		);

DELETE
FROM linii_doc_ext lde
WHERE NOT EXISTS (
		SELECT 1
		FROM mv_items_core mic
		WHERE mic.item_code = lde.item_code
		);

COMMIT;

-- ============================================================================
-- FK-uri locale catre MV_CLIENTI (replicat in VANZARI, dar original din DISTRIBUTIE)
-- ============================================================================
ALTER TABLE fise_clienti_ro ADD CONSTRAINT fk_fise_ro_client FOREIGN KEY (cod_client) REFERENCES mv_clienti (cod_client);

ALTER TABLE fise_clienti_ext ADD CONSTRAINT fk_fise_ext_client FOREIGN KEY (cod_client) REFERENCES mv_clienti (cod_client);

-- ============================================================================
-- FK-uri locale catre MV_ITEMS_CORE (replicat in VANZARI, dar original din CATALOG)
-- ============================================================================
ALTER TABLE linii_doc_ro ADD CONSTRAINT fk_lin_ro_item FOREIGN KEY (item_code) REFERENCES mv_items_core (item_code);

ALTER TABLE linii_doc_ext ADD CONSTRAINT fk_lin_ext_item FOREIGN KEY (item_code) REFERENCES mv_items_core (item_code);

-- ----------------------------------------------------------------------------
-- Job DBMS_SCHEDULER pentru refresh MV-uri la fiecare 60 secunde
-- ----------------------------------------------------------------------------
BEGIN
    DBMS_SCHEDULER.CREATE_JOB(
        job_name        => 'JOB_REFRESH_MVS',
        job_type        => 'PLSQL_BLOCK',
        job_action      => 'BEGIN DBMS_MVIEW.REFRESH(list => ''MV_CLIENTI,MV_ZONE,MV_ITEMS_CORE,MV_BRANDS,MV_ITEMS_CATEGORY,MV_ITEMS_TYPE,MV_ITEMS_SEASONS'', method => ''FFFFFFF'', atomic_refresh => FALSE); END;',
        start_date      => SYSTIMESTAMP,
        repeat_interval => 'FREQ=SECONDLY;INTERVAL=60',
        enabled         => TRUE,
        comments        => 'Refresh FAST al MV-urilor replicate la 60s'
    );
END;

-- ----------------------------------------------------------------------------
-- Trigger AFTER STATEMENT - verificare coerenta sum_doc vs sum_linii
-- ----------------------------------------------------------------------------
-- ============================================================================
-- Trigger pentru fragmentul RO (moneda = 'RON')
-- ============================================================================
CREATE
	OR REPLACE TRIGGER trg_coerenta_sum_ro AFTER

INSERT
	OR

UPDATE
	OR

DELETE ON linii_doc_ro

DECLARE CURSOR c IS

SELECT f.nr_document
	,f.doc_type_xrp
	,f.amount_doc AS doc_total
	,SUM(l.xrp_linie_valoare_fara_tva + l.xrp_linie_tva) AS sum_linii
FROM fise_clienti_ro f
JOIN linii_doc_ro l ON l.nr_document = f.nr_document
	AND l.doc_type_xrp = f.doc_type_xrp
GROUP BY f.nr_document
	,f.doc_type_xrp
	,f.amount_doc
HAVING ABS(f.amount_doc - SUM(l.xrp_linie_valoare_fara_tva + l.xrp_linie_tva)) > 0.01;

BEGIN
	FOR r IN c LOOP RAISE_APPLICATION_ERROR(- 20001, 'Incoerenta suma pe ' || r.nr_document || '' || r.doc_type_xrp || ' (doc=' || r.doc_total || ' vs sum_linii=' || r.sum_linii || ')');
END

LOOP;END;

-- ============================================================================
-- Trigger pentru fragmentul EXT (moneda <> 'RON')
-- ============================================================================
CREATE
	OR REPLACE TRIGGER trg_coerenta_sum_ext AFTER

INSERT
	OR

UPDATE
	OR

DELETE ON linii_doc_ext

DECLARE CURSOR c IS

SELECT f.nr_document
	,f.doc_type_xrp
	,f.amount_doc AS doc_total
	,SUM(l.xrp_linie_valoare_fara_tva + l.xrp_linie_tva) AS sum_linii
FROM fise_clienti_ext f
JOIN linii_doc_ext l ON l.nr_document = f.nr_document
	AND l.doc_type_xrp = f.doc_type_xrp
GROUP BY f.nr_document
	,f.doc_type_xrp
	,f.amount_doc
HAVING ABS(f.amount_doc - SUM(l.xrp_linie_valoare_fara_tva + l.xrp_linie_tva)) > 0.01;

BEGIN
	FOR r IN c LOOP RAISE_APPLICATION_ERROR(- 20002, 'Incoerenta suma EXT pe ' || r.nr_document || '' || r.doc_type_xrp || ' (doc=' || r.doc_total || ' vs sum_linii=' || r.sum_linii || ')');
END

LOOP;END;

-- ----------------------------------------------------------------------------
-- 8 indecsi pe coloanele cele mai filtrate + DBMS_STATS gather
-- ----------------------------------------------------------------------------
-- ============================================================================
-- Indecsi pe FISE_CLIENTI_RO (fragment H primar, moneda='RON')
-- ============================================================================
CREATE INDEX idx_fise_ro_data ON fise_clienti_ro (data_doc_efectiva);

CREATE INDEX idx_fise_ro_codcli ON fise_clienti_ro (cod_client);

CREATE INDEX idx_fise_ro_tip ON fise_clienti_ro (tip_doc);

-- ============================================================================
-- Indecsi pe FISE_CLIENTI_EXT (fragment H primar, moneda <> 'RON')
-- ============================================================================
CREATE INDEX idx_fise_ext_data ON fise_clienti_ext (data_doc_efectiva);

CREATE INDEX idx_fise_ext_codcli ON fise_clienti_ext (cod_client);

CREATE INDEX idx_fise_ext_tip ON fise_clienti_ext (tip_doc);

-- ============================================================================
-- Indecsi pe LINII_DOC_RO  LINII_DOC_EXT
-- (FK composit pe nr_doc + doc_type_xrp e indexat automat prin constraint;
--  item_code nu e in FK composit, deci il indexam explicit pentru joinuri)
-- ============================================================================
CREATE INDEX idx_lin_ro_item ON linii_doc_ro (item_code);

CREATE INDEX idx_lin_ext_item ON linii_doc_ext (item_code);

-- ============================================================================
-- Gather statistici pe intregul schema (pentru CBO)
-- ============================================================================
BEGIN
	DBMS_STATS.GATHER_SCHEMA_STATS(ownname => USER, CASCADE => TRUE);
END;





-- =============================================================================
-- Demo_Queries.sql - Query-uri demo pentru verificare si screenshots
-- =============================================================================

--======================================
-- User:  sgbd_vanzari
-- PDB:   VANZARI
-- Parola: oracle (role Normal)
--======================================


-- ----------------------------------------------------------------------------
-- Cererea SQL complexa: top 10 agenti 2024, defalcat pe zona + categorie
-- ----------------------------------------------------------------------------

-- ============================================================================
-- 1. Query simplu: verificam ca returneaza rezultate reale
-- ============================================================================

SELECT
    a.nume_agent
  , z.den_zona
  , c.name                                  AS categorie
  , SUM(ld.xrp_linie_valoare_fara_tva)      AS total_2024
FROM   v_fise_clienti  f
       JOIN v_linii_doc  ld
            ON  ld.nr_document  = f.nr_document
            AND ld.doc_type_xrp = f.doc_type_xrp
       JOIN mv_clienti  cli
            ON  cli.cod_client = f.cod_client
       JOIN mv_zone  z
            ON  z.id = cli.id_zona
       JOIN zone_agenti@lnk_distributie  za
            ON  za.id_zona = cli.id_zona
            AND f.data_doc_efectiva BETWEEN za.start_date
                                        AND NVL(za.end_date, DATE '9999-12-31')
       JOIN agenti@lnk_distributie  a
            ON  a.id = za.id_agent
       JOIN mv_items_core  ic
            ON  ic.item_code = ld.item_code
       JOIN mv_items_category  c
            ON  c.id = ic.category_id
WHERE  f.tip_doc           = 'F'
  AND  f.data_doc_efectiva >= DATE '2024-01-01'
  AND  f.data_doc_efectiva <  DATE '2025-01-01'
GROUP BY
    a.nume_agent
  , z.den_zona
  , c.name
ORDER BY
    total_2024 DESC
FETCH FIRST 10 ROWS ONLY;


-- ============================================================================
-- 2. Plan RBO (HINT *+ RULE *) -- Ingres-like, heuristic
-- ============================================================================

EXPLAIN PLAN SET STATEMENT_ID = 'Q_RBO' FOR
SELECT *+ RULE *
    a.nume_agent
  , z.den_zona
  , c.name                                  AS categorie
  , SUM(ld.xrp_linie_valoare_fara_tva)      AS total_2024
FROM   v_fise_clienti  f
       JOIN v_linii_doc  ld
            ON  ld.nr_document  = f.nr_document
            AND ld.doc_type_xrp = f.doc_type_xrp
       JOIN mv_clienti  cli
            ON  cli.cod_client = f.cod_client
       JOIN mv_zone  z
            ON  z.id = cli.id_zona
       JOIN zone_agenti@lnk_distributie  za
            ON  za.id_zona = cli.id_zona
            AND f.data_doc_efectiva BETWEEN za.start_date
                                        AND NVL(za.end_date, DATE '9999-12-31')
       JOIN agenti@lnk_distributie  a
            ON  a.id = za.id_agent
       JOIN mv_items_core  ic
            ON  ic.item_code = ld.item_code
       JOIN mv_items_category  c
            ON  c.id = ic.category_id
WHERE  f.tip_doc           = 'F'
  AND  f.data_doc_efectiva >= DATE '2024-01-01'
  AND  f.data_doc_efectiva <  DATE '2025-01-01'
GROUP BY
    a.nume_agent
  , z.den_zona
  , c.name
ORDER BY
    total_2024 DESC
FETCH FIRST 10 ROWS ONLY;

SELECT plan_table_output
FROM   TABLE(DBMS_XPLAN.DISPLAY(NULL, 'Q_RBO', 'BASIC +ROWS +COST'));


-- ============================================================================
-- 3. Plan CBO default -- System R-like, cost-based dynamic programming
-- ============================================================================

EXPLAIN PLAN SET STATEMENT_ID = 'Q_CBO' FOR
SELECT
    a.nume_agent
  , z.den_zona
  , c.name                                  AS categorie
  , SUM(ld.xrp_linie_valoare_fara_tva)      AS total_2024
FROM   v_fise_clienti  f
       JOIN v_linii_doc  ld
            ON  ld.nr_document  = f.nr_document
            AND ld.doc_type_xrp = f.doc_type_xrp
       JOIN mv_clienti  cli
            ON  cli.cod_client = f.cod_client
       JOIN mv_zone  z
            ON  z.id = cli.id_zona
       JOIN zone_agenti@lnk_distributie  za
            ON  za.id_zona = cli.id_zona
            AND f.data_doc_efectiva BETWEEN za.start_date
                                        AND NVL(za.end_date, DATE '9999-12-31')
       JOIN agenti@lnk_distributie  a
            ON  a.id = za.id_agent
       JOIN mv_items_core  ic
            ON  ic.item_code = ld.item_code
       JOIN mv_items_category  c
            ON  c.id = ic.category_id
WHERE  f.tip_doc           = 'F'
  AND  f.data_doc_efectiva >= DATE '2024-01-01'
  AND  f.data_doc_efectiva <  DATE '2025-01-01'
GROUP BY
    a.nume_agent
  , z.den_zona
  , c.name
ORDER BY
    total_2024 DESC
FETCH FIRST 10 ROWS ONLY;

SELECT plan_table_output
FROM   TABLE(DBMS_XPLAN.DISPLAY(NULL, 'Q_CBO', 'BASIC +ROWS +COST'));


-- ============================================================================
-- 4. Plan CBO + DRIVING_SITE(a) -- System R*-like, forteaza assembly site remote
-- (intregul query e materializat in DISTRIBUTIE, datele locale sunt trase
--  prin link reverse spre site-ul AGENTI)
-- ============================================================================

EXPLAIN PLAN SET STATEMENT_ID = 'Q_DRV' FOR
SELECT *+ DRIVING_SITE(a) *
    a.nume_agent
  , z.den_zona
  , c.name                                  AS categorie
  , SUM(ld.xrp_linie_valoare_fara_tva)      AS total_2024
FROM   v_fise_clienti  f
       JOIN v_linii_doc  ld
            ON  ld.nr_document  = f.nr_document
            AND ld.doc_type_xrp = f.doc_type_xrp
       JOIN mv_clienti  cli
            ON  cli.cod_client = f.cod_client
       JOIN mv_zone  z
            ON  z.id = cli.id_zona
       JOIN zone_agenti@lnk_distributie  za
            ON  za.id_zona = cli.id_zona
            AND f.data_doc_efectiva BETWEEN za.start_date
                                        AND NVL(za.end_date, DATE '9999-12-31')
       JOIN agenti@lnk_distributie  a
            ON  a.id = za.id_agent
       JOIN mv_items_core  ic
            ON  ic.item_code = ld.item_code
       JOIN mv_items_category  c
            ON  c.id = ic.category_id
WHERE  f.tip_doc           = 'F'
  AND  f.data_doc_efectiva >= DATE '2024-01-01'
  AND  f.data_doc_efectiva <  DATE '2025-01-01'
GROUP BY
    a.nume_agent
  , z.den_zona
  , c.name
ORDER BY
    total_2024 DESC
FETCH FIRST 10 ROWS ONLY;

SELECT plan_table_output
FROM   TABLE(DBMS_XPLAN.DISPLAY(NULL, 'Q_DRV', 'BASIC +ROWS +COST'));


-- ----------------------------------------------------------------------------
-- Suita 5 teste end-to-end de validare
-- ----------------------------------------------------------------------------

-- ============================================================================
-- Test 1: Counts globale
-- ============================================================================

SELECT 'distributie.clienti'   AS t, COUNT(*) AS n FROM clienti@lnk_distributie
UNION ALL
SELECT 'distributie.zone'      ,     COUNT(*)      FROM zone@lnk_distributie
UNION ALL
SELECT 'catalog.items_core'    ,     COUNT(*)      FROM items_core@lnk_catalog
UNION ALL
SELECT 'vanzari.v_fise'        ,     COUNT(*)      FROM v_fise_clienti
UNION ALL
SELECT 'vanzari.v_linii'       ,     COUNT(*)      FROM v_linii_doc
UNION ALL
SELECT 'vanzari.mv_clienti'    ,     COUNT(*)      FROM mv_clienti
UNION ALL
SELECT 'vanzari.mv_items_core' ,     COUNT(*)      FROM mv_items_core;


-- ============================================================================
-- Test 2: Transparenta UNION ALL (view = suma fragmentelor)
-- ============================================================================

SELECT
    (SELECT COUNT(*) FROM v_fise_clienti)
  - (
        (SELECT COUNT(*) FROM fise_clienti_ro)
      + (SELECT COUNT(*) FROM fise_clienti_ext)
    )                                                AS diff_fise
FROM dual;


-- ============================================================================
-- Test 3: INSTEAD OF INSERT pe V_FISE_CLIENTI ruteaza dupa moneda
-- ============================================================================

INSERT INTO v_fise_clienti VALUES (
    77777777
  , 'TEST_RO'
  , NULL
  , 'F'
  , 'INV'
  , SYSDATE
  , NULL
  , 1
  , 'RON'
  , 100
  , 100
  , NULL
  , 'CLI000001'
  , 'Alpha Distrib SRL'
  , 'DISTR'
);

INSERT INTO v_fise_clienti VALUES (
    77777778
  , 'TEST_EUR'
  , NULL
  , 'F'
  , 'INV'
  , SYSDATE
  , NULL
  , 1
  , 'EUR'
  , 50
  , 250
  , NULL
  , 'CLI000001'
  , 'Alpha Distrib SRL'
  , 'DISTR'
);

SELECT COUNT(*) AS in_ro
FROM   fise_clienti_ro
WHERE  id = 77777777;

SELECT COUNT(*) AS in_ext
FROM   fise_clienti_ext
WHERE  id = 77777778;

ROLLBACK;


-- ============================================================================
-- Test 4: FK cross-PDB blocheaza inserarea cu client inexistent
-- ============================================================================

DECLARE
    v_failed BOOLEAN := FALSE;
BEGIN
    BEGIN
        INSERT INTO fise_clienti_ro (
            id
          , nr_document
          , tip_doc
          , doc_type_xrp
          , data_doc_efectiva
          , semn
          , moneda
          , amount_doc
          , amount_doc_ron
          , cod_client
          , denumire_client
          , clasa_client
        ) VALUES (
            88888888
          , 'BAD_FK'
          , 'F'
          , 'INV'
          , SYSDATE
          , 1
          , 'RON'
          , 100
          , 100
          , 'NONEXISTENT'
          , 'Test'
          , 'DISTR'
        );
    EXCEPTION
        WHEN OTHERS THEN
            v_failed := TRUE;
            DBMS_OUTPUT.PUT_LINE('FK OK: ' || SQLERRM);
    END;

    IF NOT v_failed THEN
        DBMS_OUTPUT.PUT_LINE('FAILED: insertul nu a fost respins!');
        ROLLBACK;
    END IF;
END;



-- ============================================================================
-- Test 5: Sync MV (forced refresh manual)
-- ============================================================================

BEGIN
    DBMS_MVIEW.REFRESH('MV_CLIENTI', method => 'F');
END;


SELECT COUNT(*) AS mv_clienti_count
FROM   mv_clienti;



