# Non-SARGable date filter (function on the column)

**Symptom:** a monthly report is slow and its cost grows with the size of the whole table, not with the size of the month.

```sql
WHERE YEAR(SubmittedAt) = 2025 AND MONTH(SubmittedAt) = 6      -- before
WHERE SubmittedAt >= '20250601' AND SubmittedAt < '20250701'    -- after
```

## Why it is slow

An index on `SubmittedAt` is sorted by the raw value, not by `YEAR(SubmittedAt)`. Once the column is wrapped in a function the optimizer cannot compute a start and end point in the index, so the predicate is not *SARGable* (Search ARGument-able). The only option is to read **every** row of the index (2,000,000 rows), compute `YEAR()` and `MONTH()` for each, and discard 96% of them.

| | Plan ([before](../../plans/01-non-sargable-date-filter__before.sqlplan) / [after](../../plans/01-non-sargable-date-filter__after.sqlplan)) |
|---|---|
| Before | `Index Scan` of `IX_Timesheet_SubmittedAt` (all 2M rows) → `Hash Match` aggregate |
| After  | `Index Seek` on `IX_Timesheet_SubmittedAt` with a range seek predicate (~76k rows) → `Hash Match` aggregate |

## The fix

Rewrite the predicate as a **half-open range on the bare column** (`>= first day` and `< first day of next month`). It returns exactly the same rows, works for every date/time type and precision, and does not need any new index.

Same family of problems, same fix:

| Non-SARGable | SARGable rewrite |
|---|---|
| `WHERE DATEDIFF(DAY, OrderDate, GETDATE()) <= 30` | `WHERE OrderDate >= DATEADD(DAY, -30, CAST(GETDATE() AS date))` |
| `WHERE CONVERT(varchar(10), CreatedAt, 120) = '2025-06-01'` | `WHERE CreatedAt >= '20250601' AND CreatedAt < '20250602'` |
| `WHERE ISNULL(Status, 0) = 3` | `WHERE Status = 3` |
| `WHERE LEFT(Code, 3) = 'ABC'` | `WHERE Code LIKE 'ABC%'` |
| `WHERE Amount * 1.2 > 1000` | `WHERE Amount > 1000 / 1.2` |

Note: `CAST(datetimeColumn AS date) = @d` is a special case that SQL Server *can* turn into a range seek, but the explicit range is clearer and portable.

Avoid `BETWEEN '20250601' AND '20250630 23:59:59.997'` - it silently depends on the column's precision.
