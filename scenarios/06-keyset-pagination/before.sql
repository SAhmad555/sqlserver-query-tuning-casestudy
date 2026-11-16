-- Scenario 06 - BEFORE
-- Admin grid "All timesheets, newest first", 50 per page, user jumps to page 30,000
-- (or an export job walks every page). OFFSET has to produce and throw away the first
-- 1,499,950 rows before it can return 50 - the cost grows linearly with the page number.
EXEC sys.sp_executesql
     N'SELECT  TimesheetId, SubmittedAt, Status, HoursWorked, ClientId, ContractorId
       FROM    dbo.Timesheet
       ORDER BY SubmittedAt DESC, TimesheetId DESC
       OFFSET (@PageNumber - 1) * @PageSize ROWS
       FETCH NEXT @PageSize ROWS ONLY;',
     N'@PageNumber int, @PageSize int',
     @PageNumber = 30000, @PageSize = 50;
