-- Scenario 05 - AFTER
-- Same call as BEFORE. With OPTION (RECOMPILE) the optimizer sees @Since = 2025-01-01,
-- estimates ~1.2M rows and chooses a single scan + hash aggregate instead of 1.2M lookups.
EXEC dbo.usp_ApprovedHoursSince @Since = '20250101';
