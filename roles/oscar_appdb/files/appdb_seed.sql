-- AppDb — backing store for the OSCAR training web app (Milestone 5).
-- The web app queries dbo.Products with a concatenated string (the injectable sink);
-- dbo.Users backs the app login. Deliberately simple training data — isolated lab only.
IF DB_ID('AppDb') IS NULL CREATE DATABASE AppDb;
GO
USE AppDb;
GO
IF OBJECT_ID('dbo.Products','U') IS NULL
CREATE TABLE dbo.Products (
    Id       INT IDENTITY PRIMARY KEY,
    Name     NVARCHAR(100),
    Category NVARCHAR(60),
    Price    DECIMAL(10,2)
);
IF OBJECT_ID('dbo.Users','U') IS NULL
CREATE TABLE dbo.Users (
    Id       INT IDENTITY PRIMARY KEY,
    Username NVARCHAR(60),
    Password NVARCHAR(100),
    Email    NVARCHAR(120)
);
GO
IF NOT EXISTS (SELECT 1 FROM dbo.Products)
INSERT dbo.Products (Name, Category, Price) VALUES
 ('Widget','Hardware',9.99), ('Gadget','Hardware',19.99),
 ('Sprocket','Parts',4.50),  ('Doohickey','Parts',12.00),
 ('Flux Capacitor','Specialty',1985.00);
GO
IF NOT EXISTS (SELECT 1 FROM dbo.Users)
INSERT dbo.Users (Username, Password, Email) VALUES
 ('webadmin','P@ssw0rd_web!','webadmin@oscar.local'),
 ('appsvc','AppSvc_P@ss1','appsvc@oscar.local');
GO
