-- Scenario 05 - the fix
-- OPTION (RECOMPILE) on the one sensitive statement: it is compiled for the actual @Since on
-- every call. Compile cost here is a few milliseconds, negligible for a reporting query that
-- runs every 15 minutes. (See README.md in this folder for the alternatives and their trade-offs.)
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
    GROUP BY t.ClientId
    OPTION (RECOMPILE);
END
GO

-- Same "unlucky" first call as before - it no longer poisons the cache.
EXEC dbo.usp_ApprovedHoursSince @Since = '20260914';
GO
