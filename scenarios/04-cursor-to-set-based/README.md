# Cursor (RBAR) to set-based UPDATE

**Symptom:** a nightly job that refreshes invoice balances (`AmountPaid`, `Status`) takes seconds per month of invoices and gets slower every year. CPU is moderate, but the job spends most of its time *waiting*.

## Why it is slow

The legacy procedure processes one invoice at a time ("Row By Agonizing Row"): for each of the ~18,500 invoices raised in June 2025 it runs a `FETCH`, a `SELECT SUM()` against `Payment`, a `SELECT` of the invoice and an `UPDATE`. That is **~74,000 individual statements**, each with:

- its own plan lookup and execution start-up,
- its own seek from the root of the index (3 page reads even when the page was just read),
- its own lock acquisition and, because each `UPDATE` auto-commits, **its own transaction log flush** (`WRITELOG` wait). That is why elapsed time is much larger than CPU time.

Measured with `sys.dm_exec_session_wait_stats` for one run of `before.sql` on the benchmark machine: **18,459 `WRITELOG` waits totalling 2,064 ms** - exactly one log flush per invoice, and the majority of the elapsed time.

| | Plans |
|---|---|
| Before | tens of thousands of tiny plans - the first actual plan of each distinct statement is captured: [first FETCH (populates the cursor's keyset worktable)](../../plans/04-cursor-to-set-based__before_1.sqlplan), [SUM of payments](../../plans/04-cursor-to-set-based__before_2.sqlplan), [read gross](../../plans/04-cursor-to-set-based__before_3.sqlplan), [UPDATE](../../plans/04-cursor-to-set-based__before_4.sqlplan), [FETCH inside the loop](../../plans/04-cursor-to-set-based__before_5.sqlplan) |
| After | **one** plan: [scan Payment → hash aggregate → hash join to Invoice → sort → clustered index update](../../plans/04-cursor-to-set-based__after.sqlplan) |

## The fix

Describe the *result*, not the *procedure*: aggregate all payments once, join to the invoices, update them in one statement.

```sql
UPDATE i
SET    i.AmountPaid = ISNULL(p.Paid, 0),
       i.Status     = CASE WHEN ISNULL(p.Paid, 0) = 0 THEN 1
                           WHEN p.Paid < i.GrossAmount THEN 2 ELSE 3 END
FROM   dbo.Invoice i
LEFT JOIN (SELECT InvoiceId, Paid = SUM(Amount) FROM dbo.Payment GROUP BY InvoiceId) p
       ON p.InvoiceId = i.InvoiceId
WHERE  i.InvoiceDate >= '20250601' AND i.InvoiceDate < '20250701';
```

One plan, one transaction, one log flush, and the optimizer is free to pick hash joins and sequential scans instead of 18,500 × 4 random seeks.

## Notes for production

- Very large set-based updates should be **batched** (e.g. 5,000-50,000 rows per transaction) to keep the log and lock footprint under control - that is still set-based, not RBAR.
- Wrapping the cursor in one explicit transaction removes the per-row log flush and helps somewhat, but it keeps every other per-row cost. `LOCAL FAST_FORWARD` cursors are cheaper than default cursors for the same reason - they are a mitigation, not a fix.
- Cursors are legitimately useful for administrative loops (per database, per table) or when each row must call something external - not for row-wise arithmetic.
