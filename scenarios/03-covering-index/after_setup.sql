-- Scenario 03 - the fix: a composite, covering index.
--   * Key (ClientId, WeekEnding): equality column first, then the range column -> one seek
--     lands exactly on the client's quarter.
--   * INCLUDE the remaining columns the query reads, so no Key Lookups are needed.
-- After this index exists, IX_Timesheet_ClientId is redundant (same leading key) and could be
-- dropped to save write overhead - left in place here so that before_setup.sql can restore the
-- exact starting state and the benchmark stays repeatable.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Timesheet_ClientId_WeekEnding'
                                           AND object_id = OBJECT_ID(N'dbo.Timesheet'))
    CREATE INDEX IX_Timesheet_ClientId_WeekEnding
        ON dbo.Timesheet (ClientId, WeekEnding)
        INCLUDE (Status, ContractorId, HoursWorked, OvertimeHours);
