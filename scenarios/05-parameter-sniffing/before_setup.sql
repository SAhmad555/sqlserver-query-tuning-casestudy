-- Scenario 05 - state for BEFORE
-- An incremental "approved hours by client since @Since" procedure, used every 15 minutes
-- by an integration (tiny window) and occasionally for a full re-sync (huge window).
CREATE OR ALTER PROCEDURE dbo.usp_ApprovedHoursSince
    @Since datetime2(0)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  t.ClientId,
            Timesheets = COUNT(*),
            Hours      = SUM(t.HoursWorked)
    FROM    dbo.Timesheet t
    WHERE   t.SubmittedAt >= @Since
      AND   t.Status       = 3
    GROUP BY t.ClientId;
END
GO

-- The plan is compiled and cached by the first caller: the 15-minute integration, asking for
-- the last few days (a few hundred rows). The optimizer sniffs that value and picks
-- "seek IX_Timesheet_SubmittedAt + Key Lookup per row" - perfect for a few hundred rows.
EXEC sys.sp_recompile N'dbo.usp_ApprovedHoursSince';
GO
EXEC dbo.usp_ApprovedHoursSince @Since = '20260914';
GO
