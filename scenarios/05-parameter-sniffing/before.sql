-- Scenario 05 - BEFORE
-- Month-end re-sync: everything since 1 Jan 2025 (~1.2M rows). The procedure REUSES the
-- cached "small window" plan, so it performs a Key Lookup for every one of those rows.
EXEC dbo.usp_ApprovedHoursSince @Since = '20250101';
