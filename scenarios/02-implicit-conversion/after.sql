-- Scenario 02 - AFTER
-- Parameter typed to match the column (in .NET: Parameters.Add("@ExternalRef", SqlDbType.VarChar, 20)).
-- No conversion on the column side -> index seek on IX_Timesheet_ExternalRef.
EXEC sys.sp_executesql
     N'SELECT TimesheetId, ClientId, ContractorId, WeekEnding, HoursWorked, Status
       FROM   dbo.Timesheet
       WHERE  ExternalRef = @ExternalRef;',
     N'@ExternalRef varchar(20)',
     @ExternalRef = 'TS-3837288-48';
