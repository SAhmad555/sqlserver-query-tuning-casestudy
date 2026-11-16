/*
    01_schema.sql
    Fictional domain: a contractor staffing agency.
      Client      - companies that hire contractors through the agency
      Contractor  - the people doing the work
      Placement   - a contractor assigned to a client at a pay/charge rate
      Timesheet   - weekly hours per placement (largest table, ~2M rows)
      Invoice     - one invoice per placement per calendar month of approved timesheets
      Payment     - cash received against invoices

    The indexes below are the "starting point" a typical OLTP system would have:
    primary keys, foreign-key support indexes and a few single-column indexes.
    Each scenario adds or changes indexes/code from here.
*/
USE TuningDemo;
GO
SET NOCOUNT ON;

DROP TABLE IF EXISTS dbo.Payment, dbo.Timesheet, dbo.Invoice, dbo.Placement, dbo.Contractor, dbo.Client;
GO

CREATE TABLE dbo.Client
(
    ClientId        int           NOT NULL CONSTRAINT PK_Client PRIMARY KEY CLUSTERED,
    ClientCode      varchar(10)   NOT NULL CONSTRAINT UQ_Client_ClientCode UNIQUE,
    ClientName      nvarchar(100) NOT NULL,
    Region          char(2)       NOT NULL,
    PaymentTermDays smallint      NOT NULL,
    CreatedAt       datetime2(0)  NOT NULL
);

CREATE TABLE dbo.Contractor
(
    ContractorId    int           NOT NULL CONSTRAINT PK_Contractor PRIMARY KEY CLUSTERED,
    ContractorRef   varchar(12)   NOT NULL CONSTRAINT UQ_Contractor_Ref UNIQUE,
    FirstName       nvarchar(50)  NOT NULL,
    LastName        nvarchar(50)  NOT NULL,
    Email           varchar(120)  NOT NULL,
    Region          char(2)       NOT NULL,
    IsActive        bit           NOT NULL,
    CreatedAt       datetime2(0)  NOT NULL
);

CREATE TABLE dbo.Placement
(
    PlacementId     int           NOT NULL CONSTRAINT PK_Placement PRIMARY KEY CLUSTERED,
    ContractorId    int           NOT NULL CONSTRAINT FK_Placement_Contractor REFERENCES dbo.Contractor (ContractorId),
    ClientId        int           NOT NULL CONSTRAINT FK_Placement_Client     REFERENCES dbo.Client (ClientId),
    StartDate       date          NOT NULL,
    EndDate         date          NOT NULL,
    PayRate         decimal(9,2)  NOT NULL,
    ChargeRate      decimal(9,2)  NOT NULL,
    JobTitle        nvarchar(60)  NOT NULL
);
CREATE INDEX IX_Placement_ContractorId ON dbo.Placement (ContractorId);
CREATE INDEX IX_Placement_ClientId     ON dbo.Placement (ClientId);

CREATE TABLE dbo.Invoice
(
    InvoiceId       int           NOT NULL CONSTRAINT PK_Invoice PRIMARY KEY CLUSTERED,
    InvoiceNumber   varchar(16)   NOT NULL CONSTRAINT UQ_Invoice_Number UNIQUE,
    ClientId        int           NOT NULL CONSTRAINT FK_Invoice_Client    REFERENCES dbo.Client (ClientId),
    PlacementId     int           NOT NULL CONSTRAINT FK_Invoice_Placement REFERENCES dbo.Placement (PlacementId),
    PeriodEnd       date          NOT NULL,
    InvoiceDate     date          NOT NULL,
    DueDate         date          NOT NULL,
    NetAmount       decimal(12,2) NOT NULL,
    VatAmount       decimal(12,2) NOT NULL,
    GrossAmount     decimal(12,2) NOT NULL,
    AmountPaid      decimal(12,2) NOT NULL CONSTRAINT DF_Invoice_AmountPaid DEFAULT (0),
    Status          tinyint       NOT NULL   -- 1 = Open, 2 = Part paid, 3 = Paid
);
CREATE INDEX IX_Invoice_ClientId    ON dbo.Invoice (ClientId);
CREATE INDEX IX_Invoice_InvoiceDate ON dbo.Invoice (InvoiceDate);

CREATE TABLE dbo.Timesheet
(
    TimesheetId     int           NOT NULL CONSTRAINT PK_Timesheet PRIMARY KEY CLUSTERED,
    PlacementId     int           NOT NULL CONSTRAINT FK_Timesheet_Placement  REFERENCES dbo.Placement (PlacementId),
    ContractorId    int           NOT NULL CONSTRAINT FK_Timesheet_Contractor REFERENCES dbo.Contractor (ContractorId),
    ClientId        int           NOT NULL CONSTRAINT FK_Timesheet_Client     REFERENCES dbo.Client (ClientId),
    WeekEnding      date          NOT NULL,
    HoursWorked     decimal(5,2)  NOT NULL,
    OvertimeHours   decimal(5,2)  NOT NULL,
    Status          tinyint       NOT NULL,  -- 1 = Draft, 2 = Submitted, 3 = Approved, 4 = Rejected
    SubmittedAt     datetime2(0)  NOT NULL,
    ApprovedAt      datetime2(0)  NULL,
    ExternalRef     varchar(20)   NOT NULL,  -- reference from the client's own portal
    InvoiceId       int           NULL CONSTRAINT FK_Timesheet_Invoice REFERENCES dbo.Invoice (InvoiceId),
    Notes           nvarchar(200) NULL
);
-- Starting-point indexes (deliberately "typical", not tuned)
CREATE INDEX IX_Timesheet_ClientId    ON dbo.Timesheet (ClientId);
CREATE INDEX IX_Timesheet_PlacementId ON dbo.Timesheet (PlacementId);
CREATE INDEX IX_Timesheet_InvoiceId   ON dbo.Timesheet (InvoiceId);
CREATE INDEX IX_Timesheet_ExternalRef ON dbo.Timesheet (ExternalRef);
CREATE INDEX IX_Timesheet_SubmittedAt ON dbo.Timesheet (SubmittedAt) INCLUDE (Status, HoursWorked);

CREATE TABLE dbo.Payment
(
    PaymentId       int           NOT NULL CONSTRAINT PK_Payment PRIMARY KEY CLUSTERED,
    InvoiceId       int           NOT NULL CONSTRAINT FK_Payment_Invoice REFERENCES dbo.Invoice (InvoiceId),
    PaymentDate     date          NOT NULL,
    Amount          decimal(12,2) NOT NULL,
    Method          varchar(10)   NOT NULL   -- BACS, CARD, CHEQUE
);
CREATE INDEX IX_Payment_InvoiceId ON dbo.Payment (InvoiceId);
GO
