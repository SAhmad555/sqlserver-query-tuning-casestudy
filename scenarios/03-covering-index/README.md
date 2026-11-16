# Missing covering index (scan / key lookups)

**Symptom:** a client-portal report for *one* client and *one* quarter reads the entire 2,000,000-row table.

```sql
WHERE ClientId = @ClientId AND WeekEnding >= @From AND WeekEnding < @To AND Status = 3
-- reads WeekEnding, ContractorId, HoursWorked, OvertimeHours
```

## Why it is slow

The table has a single-column index `IX_Timesheet_ClientId (ClientId)`. For client 5 it would find 60,000 rows - but none of the other columns the query needs are in that index, so each row would need a **Key Lookup** into the clustered index (~3 page reads each, ~180,000 reads in total). The optimizer correctly decides that is worse than reading the whole table once (the *tipping point*), and chooses a **Clustered Index Scan** of all 20,365 pages, filtering down to ~6,300 rows.

Either way - lookups or scan - the cost is driven by rows the query never returns.

| | Plan ([before](../../plans/03-covering-index__before.sqlplan) / [after](../../plans/03-covering-index__after.sqlplan)) |
|---|---|
| Before | `Clustered Index Scan` of `PK_Timesheet` (2M rows) → hash aggregates → sort |
| After  | `Index Seek` on `IX_Timesheet_ClientId_WeekEnding` - seek on **both** ClientId and the WeekEnding range (~6,300 rows) → hash aggregates → sort |

## The fix

```sql
CREATE INDEX IX_Timesheet_ClientId_WeekEnding
    ON dbo.Timesheet (ClientId, WeekEnding)
    INCLUDE (Status, ContractorId, HoursWorked, OvertimeHours);
```

Design rules applied:

1. **Equality columns first, then the range column** in the key: `(ClientId, WeekEnding)` turns the predicate into one contiguous range in the index.
2. **INCLUDE** the columns that are only read (or filtered with low selectivity, like `Status`). They live only in the leaf level, so the key stays narrow.
3. **Don't keep redundant indexes.** `IX_Timesheet_ClientId` is now a left-prefix of the new index and is a candidate to drop (every index costs on INSERT/UPDATE and in maintenance). Check `sys.dm_db_index_usage_stats` before dropping in a real system.

## Trade-offs to discuss with the client

- Every index slows writes slightly and uses space (this one: roughly the size of 4-5 narrow columns × 2M rows).
- Don't blindly create every "missing index" the DMVs / plan warnings suggest - they are per-query, overlap heavily and ignore write cost. Consolidate them into a few well-designed indexes.
