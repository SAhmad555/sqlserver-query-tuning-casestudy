-- Scenario 01 - AFTER
-- Same result, expressed as a half-open range on the bare column (SARGable):
-- the optimizer can seek straight to June 2025 in IX_Timesheet_SubmittedAt.
SELECT  Status,
        Timesheets = COUNT(*),
        Hours      = SUM(HoursWorked)
FROM    dbo.Timesheet
WHERE   SubmittedAt >= '20250601'
  AND   SubmittedAt <  '20250701'
GROUP BY Status;
