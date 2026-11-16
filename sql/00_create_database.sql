/*
    00_create_database.sql
    Creates the TuningDemo database on the local instance.
    Target: SQL Server LocalDB  (localdb)\MSSQLLocalDB  -- any SQL Server 2019+ works.

    sqlcmd -S "(localdb)\MSSQLLocalDB" -E -C -i sql\00_create_database.sql
*/
USE master;
GO
IF DB_ID(N'TuningDemo') IS NOT NULL
BEGIN
    ALTER DATABASE TuningDemo SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE TuningDemo;
END
GO
CREATE DATABASE TuningDemo;
GO
ALTER DATABASE TuningDemo SET RECOVERY SIMPLE;
-- Express/LocalDB creates databases with AUTO_CLOSE ON: the database (and its cached plans)
-- would be closed every time the last connection disconnects. Never what you want.
ALTER DATABASE TuningDemo SET AUTO_CLOSE OFF;
-- Pre-size so the seed does not spend its time in autogrowth.
ALTER DATABASE TuningDemo MODIFY FILE (NAME = N'TuningDemo',     SIZE = 1024MB, FILEGROWTH = 256MB);
ALTER DATABASE TuningDemo MODIFY FILE (NAME = N'TuningDemo_log', SIZE = 512MB,  FILEGROWTH = 256MB);
GO
SELECT name, compatibility_level, collation_name, recovery_model_desc
FROM sys.databases WHERE name = N'TuningDemo';
GO
