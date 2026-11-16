-- Scenario 02 - BEFORE
-- What an application sends when it uses SqlCommand.Parameters.AddWithValue("@ExternalRef", "...")
-- or an ORM maps a .NET string without a column type: the parameter is NVARCHAR(4000).
-- ExternalRef is VARCHAR(20) with a SQL_* collation, so the column side must be converted
-- (CONVERT_IMPLICIT) for every row -> index SCAN instead of a seek.
EXEC sys.sp_executesql
     N'SELECT TimesheetId, ClientId, ContractorId, WeekEnding, HoursWorked, Status
       FROM   dbo.Timesheet
       WHERE  ExternalRef = @ExternalRef;',
     N'@ExternalRef nvarchar(4000)',
     @ExternalRef = N'TS-3837288-48';
