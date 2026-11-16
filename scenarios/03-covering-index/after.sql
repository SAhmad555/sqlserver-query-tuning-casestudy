-- Scenario 03 - AFTER
-- Query text is unchanged; only the index (after_setup.sql) is new.
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
