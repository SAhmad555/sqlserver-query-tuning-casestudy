-- Scenario 03 - state for BEFORE: only the single-column IX_Timesheet_ClientId exists.
DROP INDEX IF EXISTS IX_Timesheet_ClientId_WeekEnding ON dbo.Timesheet;
