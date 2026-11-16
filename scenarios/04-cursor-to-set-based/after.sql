-- Scenario 04 - AFTER
-- The same business rule as ONE set-based statement: aggregate the payments once,
-- join to the invoices, update everything in a single pass.
SET NOCOUNT ON;

UPDATE i
SET    i.AmountPaid = ISNULL(p.Paid, 0),
       i.Status     = CASE WHEN ISNULL(p.Paid, 0) = 0  THEN 1
                           WHEN p.Paid < i.GrossAmount THEN 2
                           ELSE 3 END
FROM   dbo.Invoice i
LEFT JOIN (SELECT   InvoiceId, Paid = SUM(Amount)
           FROM     dbo.Payment
           GROUP BY InvoiceId) p
       ON p.InvoiceId = i.InvoiceId
WHERE  i.InvoiceDate >= '20250601' AND i.InvoiceDate < '20250701';
