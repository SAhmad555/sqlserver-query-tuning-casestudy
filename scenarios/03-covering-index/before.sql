-- Scenario 03 - BEFORE
-- Client portal: weekly hours for one client over a quarter.
-- The only usable index is IX_Timesheet_ClientId (ClientId). It finds the client's 60,000 rows
-- but then has to fetch WeekEnding/HoursWorked/... from the clustered index one row at a time
-- (Key Lookup), or give up and scan the whole table - whichever the optimizer guesses is cheaper.
EXEC sys.sp_executesql
     N'SELECT  WeekEnding,
               Contractors   = COUNT(DISTINCT ContractorId),
               Hours         = SUM(HoursWorked),
               OvertimeHours = SUM(OvertimeHours)
       FROM    dbo.Timesheet
       WHERE   ClientId    = @ClientId
         AND   WeekEnding >= @From
         AND   WeekEnding <  @To
         AND   Status      = 3
       GROUP BY WeekEnding
       ORDER BY WeekEnding;',
     N'@ClientId int, @From date, @To date',
     @ClientId = 5, @From = '20250401', @To = '20250701';
