-- Scenario 04 - BEFORE
-- Nightly "refresh invoice balances" job, written row-by-row (RBAR):
-- for every invoice raised in June 2025 (~18,500 invoices) it
--   1. sums that invoice's payments,
--   2. reads the invoice gross,
--   3. updates AmountPaid and Status.
-- That is ~55,000 separate statements, each with its own plan execution, locking and logging.
SET NOCOUNT ON;

DECLARE @InvoiceId int, @Paid decimal(12,2), @Gross decimal(12,2);

DECLARE invoice_cursor CURSOR FOR
    SELECT InvoiceId
    FROM   dbo.Invoice
    WHERE  InvoiceDate >= '20250601' AND InvoiceDate < '20250701'
    ORDER BY InvoiceId;

OPEN invoice_cursor;
FETCH NEXT FROM invoice_cursor INTO @InvoiceId;

WHILE @@FETCH_STATUS = 0
BEGIN
    SELECT @Paid = ISNULL(SUM(Amount), 0)
    FROM   dbo.Payment
    WHERE  InvoiceId = @InvoiceId;

    SELECT @Gross = GrossAmount
    FROM   dbo.Invoice
    WHERE  InvoiceId = @InvoiceId;

    UPDATE dbo.Invoice
    SET    AmountPaid = @Paid,
           Status     = CASE WHEN @Paid = 0 THEN 1
                             WHEN @Paid < @Gross THEN 2
                             ELSE 3 END
    WHERE  InvoiceId = @InvoiceId;

    FETCH NEXT FROM invoice_cursor INTO @InvoiceId;
END

CLOSE invoice_cursor;
DEALLOCATE invoice_cursor;
