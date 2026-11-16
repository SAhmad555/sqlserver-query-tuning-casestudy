# Implicit conversion (NVARCHAR parameter vs VARCHAR column)

**Symptom:** a single-row lookup by a reference number takes hundreds of milliseconds and lots of CPU, although there is an index on exactly that column. The plan shows a yellow warning triangle on the `SELECT` operator: *"Type conversion in expression (CONVERT_IMPLICIT...) may affect CardinalityEstimate / SeekPlan"*.

```csharp
// before - .NET string becomes NVARCHAR(4000)
cmd.Parameters.AddWithValue("@ExternalRef", externalRef);

// after - typed to match the column
cmd.Parameters.Add("@ExternalRef", SqlDbType.VarChar, 20).Value = externalRef;
```

(Dapper: `new DbString { Value = externalRef, IsAnsi = true, Length = 20 }`; EF Core: `.IsUnicode(false).HasMaxLength(20)` on the property.)

## Why it is slow

`Timesheet.ExternalRef` is `VARCHAR(20)`. The application sends `NVARCHAR(4000)`. `NVARCHAR` has higher data-type precedence, so SQL Server must convert the **column** to `NVARCHAR` - for every row - before it can compare. With a SQL Server collation (`SQL_Latin1_General_CP1_CI_AS`, still the default on most servers) the converted value no longer sorts like the index, so the seek becomes a full **index scan** of 2,000,000 rows plus 2,000,000 conversions.

| | Plan ([before](../../plans/02-implicit-conversion__before.sqlplan) / [after](../../plans/02-implicit-conversion__after.sqlplan)) |
|---|---|
| Before | `Index Scan` of `IX_Timesheet_ExternalRef` with predicate `CONVERT_IMPLICIT(nvarchar(20), ExternalRef) = @ExternalRef`, then `Key Lookup` |
| After  | `Index Seek` on `IX_Timesheet_ExternalRef` (1 row), then `Key Lookup` |

(With a Windows collation such as `Latin1_General_CI_AS` SQL Server can sometimes still seek, using a dynamic range - but the conversion and the warning remain. Fix the type, do not rely on the collation.)

## How to find these in production

```sql
-- Cached plans containing a column-side implicit conversion
SELECT TOP (50) qs.total_worker_time, qs.execution_count, st.text, qp.query_plan
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
WHERE CAST(qp.query_plan AS nvarchar(max)) LIKE N'%CONVERT_IMPLICIT%PlanAffectingConvert%'
ORDER BY qs.total_worker_time DESC;
```

The same problem appears with joins between columns of different types (`int` vs `varchar` codes, `varchar` vs `nvarchar` keys) - the fix there is aligning the schema.
