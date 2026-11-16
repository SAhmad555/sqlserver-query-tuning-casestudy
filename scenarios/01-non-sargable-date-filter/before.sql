-- Scenario 01 - BEFORE
-- Monthly submission report. Wrapping the column in YEAR()/MONTH() hides it from the
-- index on SubmittedAt: SQL Server must evaluate the functions for all 2,000,000 rows.
SELECT  Status,
        Timesheets = COUNT(*),
        Hours      = SUM(HoursWorked)
FROM    dbo.Timesheet
WHERE   YEAR(SubmittedAt)  = 2025
  AND   MONTH(SubmittedAt) = 6
GROUP BY Status;
