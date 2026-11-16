# Parameter sniffing (a plan cached for a tiny range reused for a huge one)

**Symptom:** "The procedure is fast most of the day, then suddenly takes seconds. When I run the same query in SSMS it's fast." Restarting the server or `sp_recompile` "fixes" it until it happens again.

## Why it is slow

`dbo.usp_ApprovedHoursSince @Since` is called every 15 minutes by an integration with a recent date (a few hundred rows) and occasionally with an old date for a re-sync (~1.27 million rows).

SQL Server compiles a procedure's plan using the parameter values of the **first** call and caches it. The first call of the day was the small one, so the cached plan is: *seek `IX_Timesheet_SubmittedAt` for the range, then a `Key Lookup` into the clustered index for every row to get `ClientId`*. Perfect for 500 rows. When the re-sync reuses it with `@Since = 2025-01-01`, it performs **~1.27 million key lookups** (about 4 million logical reads) where one scan of the table (~20,000 pages) would do.

"Fast in SSMS" happens because SSMS uses different `SET` options (`ARITHABORT ON`) than most client libraries, so it gets its own, freshly compiled plan - the classic red herring.

| | Plan ([before](../../plans/05-parameter-sniffing__before.sqlplan) / [after](../../plans/05-parameter-sniffing__after.sqlplan)) |
|---|---|
| Before | `Index Seek` (`IX_Timesheet_SubmittedAt`) → `Nested Loops` → `Key Lookup` ×1.27M → `Sort` → `Stream Aggregate` (compiled for `@Since = 2026-09-14`) |
| After  | `Clustered Index Scan` → `Hash Match` aggregate (compiled for the actual `@Since`) |

## The fix used here

`OPTION (RECOMPILE)` on the single sensitive statement: the plan is built for the actual parameter values on every call. The compile costs a few milliseconds of CPU, which is irrelevant for a reporting query that runs every 15 minutes - and it also lets the optimizer see the real values.

## The alternatives (and when to use them)

| Option | Good when | Watch out |
|---|---|---|
| `OPTION (RECOMPILE)` | Low/medium call frequency, highly variable parameters | Compile CPU on every call - not for queries running thousands of times per second |
| `OPTION (OPTIMIZE FOR (@Since = '...'))` | One "typical" value should always win | The atypical calls get a sub-optimal plan, and the hard-coded value ages |
| `OPTION (OPTIMIZE FOR UNKNOWN)` / local variables | Want a stable "average" plan | Uses density/guessed estimates (for `>=` a fixed 30% guess) - often a stable *bad* plan for everyone |
| Two procedures / branching (small window vs. full re-sync) | The workload has clearly different modes | More code to maintain |
| Better index (here: `INCLUDE (ClientId)` on `IX_Timesheet_SubmittedAt`) | The lookup is the expensive part | Removes the lookups, so both plans become cheap - often the best long-term fix, but costs write overhead |
| Plan guide / **Query Store hint** (`sys.sp_query_store_set_hints`, SQL 2022+) / plan forcing | You cannot change the code (vendor app) | Must be documented and reviewed after upgrades |

## A note on SQL Server 2022+ (measured)

SQL Server 2022 introduced **Parameter Sensitive Plan optimization** (compatibility level 160+), which caches multiple plan variants for skewed **equality** predicates. While building this case study I first wrote the demo as `WHERE ClientId = @ClientId` on a heavily skewed client column - and on this SQL Server 2025 instance (compat level 170) PSP correctly chose a scan for the big client, so the classic problem did not reproduce. PSP does **not** cover range predicates like `>= @Since`, optional parameters on older compat levels, or databases still at compat level < 160 (most migrated estates), so parameter sniffing is still very much a production issue - but check the compatibility level before reaching for hints.
