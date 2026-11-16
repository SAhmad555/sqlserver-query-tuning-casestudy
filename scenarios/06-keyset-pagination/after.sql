-- Scenario 06 - AFTER
-- Keyset ("seek") pagination: the client remembers the sort key of the last row it showed
-- (SubmittedAt, TimesheetId) and asks for the next 50 rows *after* it. The index on
-- SubmittedAt (whose key implicitly ends with the clustered key TimesheetId) lets SQL Server
-- seek straight to that position, so page 30,000 costs the same as page 1.
--
-- @LastSubmittedAt / @LastTimesheetId are the last row of page 29,999 - i.e. this returns
-- exactly the same 50 rows as before.sql:
--   SELECT TimesheetId, SubmittedAt FROM dbo.Timesheet
--   ORDER BY SubmittedAt DESC, TimesheetId DESC OFFSET 1499949 ROWS FETCH NEXT 1 ROWS ONLY;
EXEC sys.sp_executesql
     N'SELECT TOP (@PageSize)
               TimesheetId, SubmittedAt, Status, HoursWorked, ClientId, ContractorId
       FROM    dbo.Timesheet
       WHERE   SubmittedAt < @LastSubmittedAt
          OR  (SubmittedAt = @LastSubmittedAt AND TimesheetId < @LastTimesheetId)
       ORDER BY SubmittedAt DESC, TimesheetId DESC;',
     N'@LastSubmittedAt datetime2(0), @LastTimesheetId int, @PageSize int',
     @LastSubmittedAt = '2024-10-13T00:16:00', @LastTimesheetId = 1039664, @PageSize = 50;
