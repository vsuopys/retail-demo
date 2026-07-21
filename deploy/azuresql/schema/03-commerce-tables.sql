/* =============================================================================
   retail-demo :: Azure SQL OLTP source schema
   03 - Commerce transaction tables
   -----------------------------------------------------------------------------
   Denormalized transaction model:
     * sales / sale_lines            <- fact_receipts (+ fact_promotions header,
                                         + fact_promo_lines folded onto lines)
     * online_orders / *_lines       <- fact_online_order_headers / _lines
     * payments                      <- fact_payments (POS + online)

   Money is stored as DECIMAL(19,4) dollars; the lakehouse *_cents integers and
   legacy string amounts are converted during ETL (cents / 100.0).

   Each table has a BIGINT IDENTITY surrogate PK (clustered, mirror-friendly)
   plus a UNIQUE business key carried from the lakehouse *_id_ext values so ETL
   can upsert idempotently.
   ============================================================================= */

/* ---------------------------------------------------------------------------
   sales  <-  fact_receipts  (in-store POS receipt header)
     receipt-level promo (fact_promotions) folded onto the header.
   --------------------------------------------------------------------------- */
IF OBJECT_ID(N'retail.sales', N'U') IS NULL
BEGIN
    CREATE TABLE retail.sales
    (
        sale_id           BIGINT         IDENTITY(1, 1) NOT NULL,
        receipt_id        VARCHAR(64)    NOT NULL,   -- fact_receipts.receipt_id_ext
        store_id          BIGINT         NOT NULL,
        customer_id       BIGINT         NULL,       -- NULL = walk-in / non-loyalty
        sale_ts           DATETIME2(3)   NOT NULL,   -- fact_receipts.event_ts (UTC)
        receipt_type      VARCHAR(30)    NULL,
        tender_type       VARCHAR(30)    NULL,
        payment_method    VARCHAR(30)    NULL,
        subtotal_amount   DECIMAL(19, 4) NULL,
        discount_amount   DECIMAL(19, 4) NULL,
        tax_amount        DECIMAL(19, 4) NULL,
        total_amount      DECIMAL(19, 4) NULL,
        promo_code        VARCHAR(40)    NULL,       -- folded from fact_promotions
        trace_id          VARCHAR(64)    NULL,
        loaded_at         DATETIME2(3)   NOT NULL CONSTRAINT DF_sales_loaded_at DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_sales PRIMARY KEY CLUSTERED (sale_id),
        CONSTRAINT UQ_sales_receipt_id UNIQUE (receipt_id)
    );
END;
GO

/* ---------------------------------------------------------------------------
   sale_lines  <-  fact_receipt_lines  (+ fact_promo_lines discount folded in)
   --------------------------------------------------------------------------- */
IF OBJECT_ID(N'retail.sale_lines', N'U') IS NULL
BEGIN
    CREATE TABLE retail.sale_lines
    (
        sale_line_id      BIGINT         IDENTITY(1, 1) NOT NULL,
        receipt_id        VARCHAR(64)    NOT NULL,   -- FK -> retail.sales(receipt_id)
        line_number       INT            NOT NULL,   -- fact_receipt_lines.line_num
        product_id        BIGINT         NOT NULL,
        quantity          INT            NOT NULL,
        unit_price        DECIMAL(19, 4) NULL,
        extended_price    DECIMAL(19, 4) NULL,       -- fact_receipt_lines.ext_price
        promo_code        VARCHAR(40)    NULL,
        discount_amount   DECIMAL(19, 4) NULL,       -- folded from fact_promo_lines
        loaded_at         DATETIME2(3)   NOT NULL CONSTRAINT DF_sale_lines_loaded_at DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_sale_lines PRIMARY KEY CLUSTERED (sale_line_id),
        CONSTRAINT UQ_sale_lines_receipt_line UNIQUE (receipt_id, line_number)
    );
END;
GO

/* ---------------------------------------------------------------------------
   online_orders  <-  fact_online_order_headers
   --------------------------------------------------------------------------- */
IF OBJECT_ID(N'retail.online_orders', N'U') IS NULL
BEGIN
    CREATE TABLE retail.online_orders
    (
        online_order_id   BIGINT         IDENTITY(1, 1) NOT NULL,
        order_id          VARCHAR(64)    NOT NULL,   -- fact_online_order_headers.order_id_ext
        customer_id       BIGINT         NULL,
        order_ts          DATETIME2(3)   NOT NULL,   -- event_ts (UTC)
        subtotal_amount   DECIMAL(19, 4) NULL,
        tax_amount        DECIMAL(19, 4) NULL,
        total_amount      DECIMAL(19, 4) NULL,
        payment_method    VARCHAR(30)    NULL,
        loaded_at         DATETIME2(3)   NOT NULL CONSTRAINT DF_online_orders_loaded_at DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_online_orders PRIMARY KEY CLUSTERED (online_order_id),
        CONSTRAINT UQ_online_orders_order_id UNIQUE (order_id)
    );
END;
GO

/* ---------------------------------------------------------------------------
   online_order_lines  <-  fact_online_order_lines
   --------------------------------------------------------------------------- */
IF OBJECT_ID(N'retail.online_order_lines', N'U') IS NULL
BEGIN
    CREATE TABLE retail.online_order_lines
    (
        online_order_line_id  BIGINT         IDENTITY(1, 1) NOT NULL,
        order_id              VARCHAR(64)    NOT NULL,   -- FK -> retail.online_orders(order_id)
        line_number           INT            NOT NULL,   -- fact_online_order_lines.line_num
        product_id            BIGINT         NOT NULL,
        quantity              INT            NULL,
        unit_price            DECIMAL(19, 4) NULL,
        extended_price        DECIMAL(19, 4) NULL,       -- ext_price
        promo_code            VARCHAR(40)    NULL,
        fulfillment_mode      VARCHAR(30)    NULL,
        fulfillment_status    VARCHAR(30)    NULL,
        node_type             VARCHAR(30)    NULL,
        node_id               BIGINT         NULL,
        picked_ts             DATETIME2(3)   NULL,
        shipped_ts            DATETIME2(3)   NULL,
        delivered_ts          DATETIME2(3)   NULL,
        loaded_at             DATETIME2(3)   NOT NULL CONSTRAINT DF_online_order_lines_loaded_at DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_online_order_lines PRIMARY KEY CLUSTERED (online_order_line_id),
        CONSTRAINT UQ_online_order_lines_order_line UNIQUE (order_id, line_number)
    );
END;
GO

/* ---------------------------------------------------------------------------
   payments  <-  fact_payments   (settles either a POS receipt or an online order)
   --------------------------------------------------------------------------- */
IF OBJECT_ID(N'retail.payments', N'U') IS NULL
BEGIN
    CREATE TABLE retail.payments
    (
        payment_id          BIGINT         IDENTITY(1, 1) NOT NULL,
        receipt_id          VARCHAR(64)    NULL,   -- FK -> retail.sales(receipt_id)
        order_id            VARCHAR(64)    NULL,   -- FK -> retail.online_orders(order_id)
        payment_ts          DATETIME2(3)   NOT NULL,   -- event_ts (UTC)
        payment_method      VARCHAR(30)    NULL,
        amount              DECIMAL(19, 4) NULL,
        transaction_id      VARCHAR(64)    NULL,
        status              VARCHAR(20)    NULL,
        decline_reason      VARCHAR(100)   NULL,
        processing_time_ms  BIGINT         NULL,
        store_id            BIGINT         NULL,
        customer_id         BIGINT         NULL,
        loaded_at           DATETIME2(3)   NOT NULL CONSTRAINT DF_payments_loaded_at DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_payments PRIMARY KEY CLUSTERED (payment_id),
        CONSTRAINT CK_payments_target CHECK (receipt_id IS NOT NULL OR order_id IS NOT NULL)
    );
END;
GO
