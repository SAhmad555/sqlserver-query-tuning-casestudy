/*
    02_seed.sql
    Set-based, deterministic data generation (no loops, no RAND/NEWID - every run
    produces exactly the same data, so the benchmark is reproducible).

      Client        2,000
      Contractor   50,000
      Placement   100,000
      Timesheet 2,000,000   (20 consecutive weeks per placement)
      Invoice       524,558 (one per placement per month of approved hours)
      Payment       532,052 (~10% unpaid, ~10% part-paid, some paid in two instalments)

    Data skew is intentional (real systems are skewed, and parameter sniffing
    only hurts when they are):
      ClientId 1        -> 20% of all placements/timesheets  (one "key account")
      ClientId 2..11    -> 30% (3% each)
      ClientId 12..2000 -> 50% spread thinly (~0.025% each)
*/
USE TuningDemo;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @t0 datetime2 = SYSDATETIME();

------------------------------------------------------------------------------
-- Numbers (tally) table: 1..2,000,000
------------------------------------------------------------------------------
DROP TABLE IF EXISTS #N;
CREATE TABLE #N (n int NOT NULL PRIMARY KEY CLUSTERED);

WITH e1(x) AS (SELECT 1 FROM (VALUES (1),(1),(1),(1),(1),(1),(1),(1),(1),(1)) v(x)),
     e7(n) AS (SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL))
               FROM e1 a CROSS JOIN e1 b CROSS JOIN e1 c CROSS JOIN e1 d
                         CROSS JOIN e1 e CROSS JOIN e1 f CROSS JOIN e1 g)
INSERT #N WITH (TABLOCK) (n)
SELECT TOP (2000000) n FROM e7 ORDER BY n;

------------------------------------------------------------------------------
-- Clients
------------------------------------------------------------------------------
DECLARE @pre  TABLE (i int PRIMARY KEY, w nvarchar(20));
DECLARE @suf  TABLE (i int PRIMARY KEY, w nvarchar(30));
INSERT @pre VALUES (0,N'Arvel'),(1,N'Bramtor'),(2,N'Corvane'),(3,N'Dunmere'),(4,N'Elvaro'),(5,N'Fenwick Vale'),
                   (6,N'Galtrim'),(7,N'Harrowgate Ridge'),(8,N'Istvane'),(9,N'Jorvane'),(10,N'Kelmont'),(11,N'Lussara'),
                   (12,N'Morvain'),(13,N'Nethra'),(14,N'Ostrel'),(15,N'Pellavine'),(16,N'Quarnby'),(17,N'Rosk'),
                   (18,N'Sylmar'),(19,N'Tarrowby');
INSERT @suf VALUES (0,N'Engineering Ltd'),(1,N'Logistics'),(2,N'Data Services'),(3,N'Construction'),(4,N'Health Partners'),
                   (5,N'Utilities'),(6,N'Retail Group'),(7,N'Software'),(8,N'Facilities'),(9,N'Energy');

INSERT dbo.Client WITH (TABLOCK) (ClientId, ClientCode, ClientName, Region, PaymentTermDays, CreatedAt)
SELECT  n.n,
        CONCAT('CL', RIGHT(CONCAT('00000', n.n), 5)),
        CONCAT(p.w, N' ', s.w, CASE WHEN n.n > 200 THEN CONCAT(N' ', n.n / 200) ELSE N'' END),
        CHOOSE(1 + n.n % 6, 'NW', 'NE', 'MD', 'LN', 'SE', 'SW'),
        CHOOSE(1 + n.n % 3, 14, 30, 45),
        DATEADD(DAY, -(n.n * 7) % 2500, '2023-12-31')
FROM #N n
JOIN @pre p ON p.i = n.n % 20
JOIN @suf s ON s.i = (n.n / 20) % 10
WHERE n.n <= 2000;

------------------------------------------------------------------------------
-- Contractors
------------------------------------------------------------------------------
DECLARE @fn TABLE (i int PRIMARY KEY, w nvarchar(30));
DECLARE @ln TABLE (i int PRIMARY KEY, w nvarchar(30));
INSERT @fn VALUES (0,N'Aisha'),(1,N'Ben'),(2,N'Chloe'),(3,N'Daniel'),(4,N'Elena'),(5,N'Farhan'),(6,N'Grace'),(7,N'Hassan'),
                  (8,N'Isla'),(9,N'Jack'),(10,N'Kiran'),(11,N'Leah'),(12,N'Marco'),(13,N'Nadia'),(14,N'Owen'),(15,N'Priya'),
                  (16,N'Quinn'),(17,N'Rosa'),(18,N'Samir'),(19,N'Tara'),(20,N'Usman'),(21,N'Vera'),(22,N'Will'),(23,N'Yara');
INSERT @ln VALUES (0,N'Abbott'),(1,N'Bennett'),(2,N'Carver'),(3,N'Dale'),(4,N'Ellison'),(5,N'Foster'),(6,N'Gill'),(7,N'Hale'),
                  (8,N'Irwin'),(9,N'Jensen'),(10,N'Khan'),(11,N'Lowe'),(12,N'Mercer'),(13,N'Noble'),(14,N'Osei'),(15,N'Patel'),
                  (16,N'Quayle'),(17,N'Reid'),(18,N'Shaw'),(19,N'Thorne'),(20,N'Upton'),(21,N'Vance'),(22,N'Walsh'),(23,N'Young'),
                  (24,N'Zeller'),(25,N'Moreno'),(26,N'Nowak'),(27,N'Okafor'),(28,N'Silva'),(29,N'Tanaka');

INSERT dbo.Contractor WITH (TABLOCK) (ContractorId, ContractorRef, FirstName, LastName, Email, Region, IsActive, CreatedAt)
SELECT  n.n,
        CONCAT('CTR', RIGHT(CONCAT('0000000', n.n), 7)),
        f.w, l.w,
        LOWER(CONCAT(f.w, '.', l.w, '.', n.n, '@example.com')),
        CHOOSE(1 + (n.n / 7) % 6, 'NW', 'NE', 'MD', 'LN', 'SE', 'SW'),
        CASE WHEN n.n % 9 = 0 THEN 0 ELSE 1 END,
        DATEADD(DAY, -(n.n * 13) % 1500, '2024-01-01')
FROM #N n
JOIN @fn f ON f.i = n.n % 24
JOIN @ln l ON l.i = (n.n * 7) % 30
WHERE n.n <= 50000;

------------------------------------------------------------------------------
-- Placements (skewed by client)
------------------------------------------------------------------------------
INSERT dbo.Placement WITH (TABLOCK) (PlacementId, ContractorId, ClientId, StartDate, EndDate, PayRate, ChargeRate, JobTitle)
SELECT  n.n,
        1 + CAST((CAST(n.n AS bigint) * 104729) % 50000 AS int),
        x.ClientId,
        DATEADD(DAY, -6, x.FirstWeekEnding),
        DATEADD(WEEK, 19, x.FirstWeekEnding),
        x.PayRate,
        CAST(x.PayRate * 1.28 AS decimal(9,2)),
        CHOOSE(1 + n.n % 12, N'Software Developer', N'Project Manager', N'Site Engineer', N'Business Analyst',
                             N'Payroll Administrator', N'Electrician', N'Data Engineer', N'HGV Driver',
                             N'Registered Nurse', N'QA Tester', N'Quantity Surveyor', N'Warehouse Operative')
FROM #N n
CROSS APPLY (SELECT ClientId = CASE WHEN n.n % 10 IN (0,1)   THEN 1
                                    WHEN n.n % 10 IN (2,3,4) THEN 2 + (n.n / 10) % 10
                                    ELSE 12 + CAST((CAST(n.n AS bigint) * 7919) % 1989 AS int) END,
                    FirstWeekEnding = DATEADD(WEEK, (n.n * 37) % 122, CAST('2024-01-07' AS date)),  -- Sundays
                    PayRate = CAST(15 + (n.n * 13) % 80 + (n.n % 4) * 0.25 AS decimal(9,2))) x
WHERE n.n <= 100000;

------------------------------------------------------------------------------
-- Timesheets: 20 consecutive weeks for each placement = 2,000,000 rows
-- Non-clustered indexes are disabled during the load and rebuilt afterwards.
------------------------------------------------------------------------------
ALTER INDEX IX_Timesheet_ClientId    ON dbo.Timesheet DISABLE;
ALTER INDEX IX_Timesheet_PlacementId ON dbo.Timesheet DISABLE;
ALTER INDEX IX_Timesheet_InvoiceId   ON dbo.Timesheet DISABLE;
ALTER INDEX IX_Timesheet_ExternalRef ON dbo.Timesheet DISABLE;
ALTER INDEX IX_Timesheet_SubmittedAt ON dbo.Timesheet DISABLE;

INSERT dbo.Timesheet WITH (TABLOCK)
       (TimesheetId, PlacementId, ContractorId, ClientId, WeekEnding, HoursWorked, OvertimeHours,
        Status, SubmittedAt, ApprovedAt, ExternalRef, InvoiceId, Notes)
SELECT  n.n,
        p.PlacementId,
        p.ContractorId,
        p.ClientId,
        w.WeekEnding,
        CAST(20 + (n.n * 17) % 25 + (n.n % 2) * 0.5 AS decimal(5,2)),
        CAST(CASE WHEN n.n % 7 = 0 THEN n.n % 9 ELSE 0 END AS decimal(5,2)),
        s.Status,
        s.SubmittedAt,
        CASE WHEN s.Status = 3 THEN DATEADD(HOUR, 1 + n.n % 48, s.SubmittedAt) END,
        CONCAT('TS-', RIGHT(CONCAT('0000000', CAST((CAST(n.n AS bigint) * 48271) % 9999991 AS int)), 7), '-', n.n % 97),
        NULL,
        CASE n.n % 10 WHEN 0 THEN N'Worked on site all week'
                      WHEN 5 THEN N'Includes travel day' END
FROM #N n
JOIN dbo.Placement p ON p.PlacementId = 1 + (n.n - 1) % 100000
CROSS APPLY (SELECT WeekEnding = DATEADD(WEEK, (n.n - 1) / 100000, DATEADD(DAY, 6, p.StartDate))) w
CROSS APPLY (SELECT Status = CASE WHEN w.WeekEnding > '2026-09-06' THEN 1 + n.n % 3
                                  WHEN n.n % 50 = 0 THEN 4
                                  ELSE 3 END,
                    SubmittedAt = DATEADD(MINUTE, (CAST(n.n AS bigint) * 7919) % 4320,
                                          CAST(w.WeekEnding AS datetime2(0)))) s;

------------------------------------------------------------------------------
-- Invoices: one per placement per calendar month of approved hours (up to Aug 2026)
------------------------------------------------------------------------------
INSERT dbo.Invoice WITH (TABLOCK)
       (InvoiceId, InvoiceNumber, ClientId, PlacementId, PeriodEnd, InvoiceDate, DueDate,
        NetAmount, VatAmount, GrossAmount, AmountPaid, Status)
SELECT  i.InvoiceId,
        CONCAT('INV', RIGHT(CONCAT('00000000', i.InvoiceId), 8)),
        i.ClientId, i.PlacementId, i.PeriodEnd,
        DATEADD(DAY, 3, i.PeriodEnd),
        DATEADD(DAY, 3 + c.PaymentTermDays, i.PeriodEnd),
        i.NetAmount,
        CAST(i.NetAmount * 0.20 AS decimal(12,2)),
        CAST(i.NetAmount * 1.20 AS decimal(12,2)),
        0, 1
FROM (
    SELECT  InvoiceId   = CAST(ROW_NUMBER() OVER (ORDER BY g.PeriodEnd, g.PlacementId) AS int),
            g.ClientId, g.PlacementId, g.PeriodEnd, g.NetAmount
    FROM (
        SELECT  t.PlacementId, t.ClientId,
                PeriodEnd = EOMONTH(t.WeekEnding),
                NetAmount = CAST(SUM((t.HoursWorked + t.OvertimeHours * 1.5) * p.ChargeRate) AS decimal(12,2))
        FROM dbo.Timesheet t
        JOIN dbo.Placement p ON p.PlacementId = t.PlacementId
        WHERE t.Status = 3 AND t.WeekEnding <= '2026-08-31'
        GROUP BY t.PlacementId, t.ClientId, EOMONTH(t.WeekEnding)
    ) g
) i
JOIN dbo.Client c ON c.ClientId = i.ClientId;

UPDATE t
SET    t.InvoiceId = i.InvoiceId
FROM   dbo.Timesheet t
JOIN   dbo.Invoice  i ON i.PlacementId = t.PlacementId AND i.PeriodEnd = EOMONTH(t.WeekEnding)
WHERE  t.Status = 3 AND t.WeekEnding <= '2026-08-31';

------------------------------------------------------------------------------
-- Payments: ~10% unpaid, ~10% part-paid, the rest paid (1/7 of those in two instalments)
------------------------------------------------------------------------------
INSERT dbo.Payment WITH (TABLOCK) (PaymentId, InvoiceId, PaymentDate, Amount, Method)
SELECT  CAST(ROW_NUMBER() OVER (ORDER BY x.PaymentDate, x.InvoiceId, x.Seq) AS int),
        x.InvoiceId, x.PaymentDate, x.Amount,
        CHOOSE(1 + x.InvoiceId % 5, 'BACS', 'BACS', 'BACS', 'CARD', 'CHEQUE')
FROM (
    SELECT i.InvoiceId, v.Seq, v.PaymentDate, v.Amount
    FROM dbo.Invoice i
    CROSS APPLY (VALUES
        -- single full payment
        (1, DATEADD(DAY, i.InvoiceId % 40, i.InvoiceDate), i.GrossAmount, CASE WHEN i.InvoiceId % 10 > 1 AND i.InvoiceId % 7 <> 0 THEN 1 ELSE 0 END),
        -- split payment, part 1 (also used for part-paid invoices)
        (1, DATEADD(DAY, i.InvoiceId % 30, i.InvoiceDate), CAST(i.GrossAmount * 0.6 AS decimal(12,2)),
            CASE WHEN i.InvoiceId % 10 = 1 OR (i.InvoiceId % 10 > 1 AND i.InvoiceId % 7 = 0) THEN 1 ELSE 0 END),
        -- split payment, part 2
        (2, DATEADD(DAY, 10 + i.InvoiceId % 30, i.InvoiceDate), i.GrossAmount - CAST(i.GrossAmount * 0.6 AS decimal(12,2)),
            CASE WHEN i.InvoiceId % 10 > 1 AND i.InvoiceId % 7 = 0 THEN 1 ELSE 0 END)
    ) v(Seq, PaymentDate, Amount, Keep)
    WHERE v.Keep = 1 AND i.InvoiceDate < '2026-10-15'
) x;

-- Initial invoice balances (scenario 04 re-computes these)
UPDATE i
SET    i.AmountPaid = ISNULL(p.Paid, 0),
       i.Status     = CASE WHEN ISNULL(p.Paid, 0) = 0 THEN 1
                           WHEN p.Paid < i.GrossAmount THEN 2 ELSE 3 END
FROM   dbo.Invoice i
LEFT JOIN (SELECT InvoiceId, Paid = SUM(Amount) FROM dbo.Payment GROUP BY InvoiceId) p
       ON p.InvoiceId = i.InvoiceId;

------------------------------------------------------------------------------
-- Rebuild indexes and refresh statistics
------------------------------------------------------------------------------
ALTER INDEX ALL ON dbo.Timesheet REBUILD;
ALTER INDEX ALL ON dbo.Invoice   REBUILD;
ALTER INDEX ALL ON dbo.Payment   REBUILD;
UPDATE STATISTICS dbo.Client     WITH FULLSCAN;
UPDATE STATISTICS dbo.Contractor WITH FULLSCAN;
UPDATE STATISTICS dbo.Placement  WITH FULLSCAN;
UPDATE STATISTICS dbo.Invoice    WITH FULLSCAN;
UPDATE STATISTICS dbo.Timesheet  WITH FULLSCAN;
UPDATE STATISTICS dbo.Payment    WITH FULLSCAN;

DROP TABLE #N;

SELECT  TableName = t.name,
        [Rows]    = SUM(p.rows)
FROM sys.tables t
JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1)
GROUP BY t.name
ORDER BY [Rows] DESC;

PRINT CONCAT('Seed completed in ', DATEDIFF(SECOND, @t0, SYSDATETIME()), ' s');
GO
