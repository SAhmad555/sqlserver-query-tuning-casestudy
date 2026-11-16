# Deep pagination: OFFSET/FETCH vs keyset

**Symptom:** the first pages of a grid are instant, page 30,000 takes seconds; an export that walks all pages gets slower and slower (total cost is quadratic in the number of pages).

```sql
-- before: page N
ORDER BY SubmittedAt DESC, TimesheetId DESC
OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;

-- after: "the 50 rows after the last one I showed you"
SELECT TOP (@PageSize) ...
WHERE  SubmittedAt < @LastSubmittedAt
   OR (SubmittedAt = @LastSubmittedAt AND TimesheetId < @LastTimesheetId)
ORDER BY SubmittedAt DESC, TimesheetId DESC;
```

## Why it is slow

`OFFSET 1,499,950` does not "jump" anywhere: SQL Server must produce the first 1,499,950 rows in order and throw them away. Here the optimizer reads the whole clustered index and sorts it, because walking the narrow `SubmittedAt` index would need a key lookup for every skipped row (to fetch `ClientId`/`ContractorId`). The sort needs more memory than it was granted (~78 MB) and **spills to tempdb** (6,914 pages written and read back in the captured plan, visible as a warning on the Sort operator). Memory-grant feedback adjusts the grant between executions, so some runs spill and some do not - either way the query sorts 2 million rows to return 50.

| | Plan ([before](../../plans/06-keyset-pagination__before.sqlplan) / [after](../../plans/06-keyset-pagination__after.sqlplan)) |
|---|---|
| Before | `Clustered Index Scan` (2M rows) → `Sort` (outputs 1,500,000 rows, spills to tempdb) → `Top` (keeps the last 50) |
| After  | `Index Seek` on `IX_Timesheet_SubmittedAt` to the remembered position (50 rows) → `Key Lookup` ×50 → `Top` |

## The fix

**Keyset (seek) pagination**: the client keeps the sort key of the last row it displayed - `(SubmittedAt, TimesheetId)` - and asks for the rows after it. The sort key must be **unique** (hence the `TimesheetId` tie-breaker) and must match an index order. `IX_Timesheet_SubmittedAt (SubmittedAt)` already works because every non-clustered index on a clustered table implicitly carries the clustering key (`TimesheetId`) at the end of its key.

Cost is now constant - page 30,000 costs the same as page 1.

## Trade-offs

- No random "jump to page 17,342" - you get next/previous (and first/last). For most UIs (infinite scroll, "load more", APIs, exports) that is exactly what is needed; for numbered pagers, limit how deep a user can go, or combine both (OFFSET for the first few pages).
- Results are stable while data is inserted (no duplicated / skipped rows between pages), which OFFSET does not guarantee.
- The `OR` form shown is understood by the optimizer as a single range seek here; on some versions/shapes rewriting it as `UNION ALL` of the two branches or using a row-constructor-like `SubmittedAt <= @Last AND NOT (SubmittedAt = @Last AND TimesheetId >= @LastId)` gives a cleaner seek - check the plan.
