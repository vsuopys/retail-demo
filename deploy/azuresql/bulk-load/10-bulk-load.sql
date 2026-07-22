/* =============================================================================
   retail-demo :: Azure SQL OLTP bulk load from blob CSV
   -----------------------------------------------------------------------------
   Loads the CSV files produced by fabric/lakehouse/51-silver-to-blob-csv.ipynb
   into the retail.* OLTP tables using OPENROWSET(BULK, FORMAT='CSV').

   This is the fast, set-based alternative to the row-by-row JDBC reverse-ETL in
   50-silver-to-azuresql-oltp.ipynb.

   BEFORE RUNNING replace the two placeholders below:
     __BLOB_URL__   container URL, e.g. https://myacct.blob.core.windows.net/mycontainer
     __SAS_TOKEN__  read/list SAS for that container, WITHOUT a leading '?'

   Column order matches the CSV exactly (IDENTITY PK excluded, loaded_at last).
   Both are generated from deploy/azuresql/schema/*.sql -- keep in sync.

   NOTE: Azure SQL DB OPENROWSET(BULK) reads ONE file per statement (no wildcards).
   These statements assume the notebook ran with SINGLE_FILE=True (one <table>.csv
   per table). For multi-file exports, run the loader the notebook prints instead.
   ============================================================================= */

-------------------------------------------------------------------------------
-- 0. One-time setup: master key + SAS credential + external data source
-------------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'Ch4nge-me-strong-P@ssw0rd!';
GO

IF EXISTS (SELECT 1 FROM sys.external_data_sources WHERE name = 'OltpBlobSrc')
    DROP EXTERNAL DATA SOURCE OltpBlobSrc;
IF EXISTS (SELECT 1 FROM sys.database_scoped_credentials WHERE name = 'OltpBlobCred')
    DROP DATABASE SCOPED CREDENTIAL OltpBlobCred;
GO

CREATE DATABASE SCOPED CREDENTIAL OltpBlobCred
    WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
         SECRET   = '__SAS_TOKEN__';
GO

CREATE EXTERNAL DATA SOURCE OltpBlobSrc
    WITH (TYPE = BLOB_STORAGE, LOCATION = '__BLOB_URL__', CREDENTIAL = OltpBlobCred);
GO

-------------------------------------------------------------------------------
-- 1. (Optional) Reset targets before load. Drop FKs first if enforced.
--    Uncomment to truncate in child -> parent order.
-------------------------------------------------------------------------------
/*

TRUNCATE TABLE retail.shipment_lines;
TRUNCATE TABLE retail.shipment_movements;
TRUNCATE TABLE retail.stockouts;
TRUNCATE TABLE retail.reorders;
TRUNCATE TABLE retail.inventory_transactions;
TRUNCATE TABLE retail.payments;
TRUNCATE TABLE retail.online_order_lines;
TRUNCATE TABLE retail.online_orders;
TRUNCATE TABLE retail.sale_lines;
TRUNCATE TABLE retail.sales;
TRUNCATE TABLE retail.products;
TRUNCATE TABLE retail.trucks;
TRUNCATE TABLE retail.distribution_centers;
TRUNCATE TABLE retail.stores;
TRUNCATE TABLE retail.customers;
TRUNCATE TABLE retail.geographies;
*/
GO

-------------------------------------------------------------------------------
-- 2. Load each table (parent -> child, FK-safe order). One file per statement.
--    BULK path is relative to the external data source LOCATION (container root).
--    Adjust the 'oltp-export/' prefix if you set a different BLOB_PREFIX.
-------------------------------------------------------------------------------

INSERT INTO retail.geographies (geography_id, city, state, zip_code, district, region, loaded_at)
SELECT geography_id, city, state, zip_code, district, region, loaded_at
FROM OPENROWSET(
    BULK 'oltp-export/geographies.csv',
    DATA_SOURCE   = 'OltpBlobSrc',
    FORMAT        = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW      = 2,
    FIELDQUOTE    = '"'
) WITH (
        geography_id             BIGINT,
        city                     NVARCHAR(100),
        state                    NVARCHAR(50),
        zip_code                 VARCHAR(15),
        district                 NVARCHAR(100),
        region                   NVARCHAR(100),
        loaded_at                DATETIME2(3)
) AS s;
GO

INSERT INTO retail.customers (customer_id, first_name, last_name, address, geography_id, loyalty_card, phone, ble_id, ad_id, loaded_at)
SELECT customer_id, first_name, last_name, address, geography_id, loyalty_card, phone, ble_id, ad_id, loaded_at
FROM OPENROWSET(
    BULK 'oltp-export/customers.csv',
    DATA_SOURCE   = 'OltpBlobSrc',
    FORMAT        = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW      = 2,
    FIELDQUOTE    = '"'
) WITH (
        customer_id              BIGINT,
        first_name               NVARCHAR(100),
        last_name                NVARCHAR(100),
        address                  NVARCHAR(255),
        geography_id             BIGINT,
        loyalty_card             VARCHAR(50),
        phone                    VARCHAR(30),
        ble_id                   VARCHAR(64),
        ad_id                    VARCHAR(64),
        loaded_at                DATETIME2(3)
) AS s;
GO

INSERT INTO retail.stores (store_id, store_number, address, geography_id, tax_rate, volume_class, store_format, operating_hours, daily_traffic_multiplier, loaded_at)
SELECT store_id, store_number, address, geography_id, tax_rate, volume_class, store_format, operating_hours, daily_traffic_multiplier, loaded_at
FROM OPENROWSET(
    BULK 'oltp-export/stores.csv',
    DATA_SOURCE   = 'OltpBlobSrc',
    FORMAT        = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW      = 2,
    FIELDQUOTE    = '"'
) WITH (
        store_id                 BIGINT,
        store_number             VARCHAR(20),
        address                  NVARCHAR(255),
        geography_id             BIGINT,
        tax_rate                 DECIMAL(6,4),
        volume_class             VARCHAR(20),
        store_format             VARCHAR(30),
        operating_hours          VARCHAR(50),
        daily_traffic_multiplier DECIMAL(9,4),
        loaded_at                DATETIME2(3)
) AS s;
GO

INSERT INTO retail.distribution_centers (dc_id, dc_number, address, geography_id, loaded_at)
SELECT dc_id, dc_number, address, geography_id, loaded_at
FROM OPENROWSET(
    BULK 'oltp-export/distribution_centers.csv',
    DATA_SOURCE   = 'OltpBlobSrc',
    FORMAT        = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW      = 2,
    FIELDQUOTE    = '"'
) WITH (
        dc_id                    BIGINT,
        dc_number                VARCHAR(20),
        address                  NVARCHAR(255),
        geography_id             BIGINT,
        loaded_at                DATETIME2(3)
) AS s;
GO

INSERT INTO retail.trucks (truck_id, license_plate, refrigeration, dc_id, loaded_at)
SELECT truck_id, license_plate, refrigeration, dc_id, loaded_at
FROM OPENROWSET(
    BULK 'oltp-export/trucks.csv',
    DATA_SOURCE   = 'OltpBlobSrc',
    FORMAT        = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW      = 2,
    FIELDQUOTE    = '"'
) WITH (
        truck_id                 BIGINT,
        license_plate            VARCHAR(20),
        refrigeration            BIT,
        dc_id                    BIGINT,
        loaded_at                DATETIME2(3)
) AS s;
GO

INSERT INTO retail.products (product_id, product_name, brand, company, department, category, subcategory, cost, msrp, sale_price, requires_refrigeration, launch_date, taxability, tags, loaded_at)
SELECT product_id, product_name, brand, company, department, category, subcategory, cost, msrp, sale_price, requires_refrigeration, launch_date, taxability, tags, loaded_at
FROM OPENROWSET(
    BULK 'oltp-export/products.csv',
    DATA_SOURCE   = 'OltpBlobSrc',
    FORMAT        = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW      = 2,
    FIELDQUOTE    = '"'
) WITH (
        product_id               BIGINT,
        product_name             NVARCHAR(200),
        brand                    NVARCHAR(100),
        company                  NVARCHAR(100),
        department               NVARCHAR(100),
        category                 NVARCHAR(100),
        subcategory              NVARCHAR(100),
        cost                     DECIMAL(19,4),
        msrp                     DECIMAL(19,4),
        sale_price               DECIMAL(19,4),
        requires_refrigeration   BIT,
        launch_date              DATETIME2(3),
        taxability               VARCHAR(30),
        tags                     NVARCHAR(500),
        loaded_at                DATETIME2(3)
) AS s;
GO

INSERT INTO retail.sales (receipt_id, store_id, customer_id, sale_ts, receipt_type, tender_type, payment_method, subtotal_amount, discount_amount, tax_amount, total_amount, promo_code, trace_id, loaded_at)
SELECT receipt_id, store_id, customer_id, sale_ts, receipt_type, tender_type, payment_method, subtotal_amount, discount_amount, tax_amount, total_amount, promo_code, trace_id, loaded_at
FROM OPENROWSET(
    BULK 'oltp-export/sales.csv',
    DATA_SOURCE   = 'OltpBlobSrc',
    FORMAT        = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW      = 2,
    FIELDQUOTE    = '"'
) WITH (
        receipt_id               VARCHAR(64),
        store_id                 BIGINT,
        customer_id              BIGINT,
        sale_ts                  DATETIME2(3),
        receipt_type             VARCHAR(30),
        tender_type              VARCHAR(30),
        payment_method           VARCHAR(30),
        subtotal_amount          DECIMAL(19,4),
        discount_amount          DECIMAL(19,4),
        tax_amount               DECIMAL(19,4),
        total_amount             DECIMAL(19,4),
        promo_code               VARCHAR(40),
        trace_id                 VARCHAR(64),
        loaded_at                DATETIME2(3)
) AS s;
GO

INSERT INTO retail.sale_lines (receipt_id, line_number, product_id, quantity, unit_price, extended_price, promo_code, discount_amount, loaded_at)
SELECT receipt_id, line_number, product_id, quantity, unit_price, extended_price, promo_code, discount_amount, loaded_at
FROM OPENROWSET(
    BULK 'oltp-export/sale_lines.csv',
    DATA_SOURCE   = 'OltpBlobSrc',
    FORMAT        = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW      = 2,
    FIELDQUOTE    = '"'
) WITH (
        receipt_id               VARCHAR(64),
        line_number              INT,
        product_id               BIGINT,
        quantity                 INT,
        unit_price               DECIMAL(19,4),
        extended_price           DECIMAL(19,4),
        promo_code               VARCHAR(40),
        discount_amount          DECIMAL(19,4),
        loaded_at                DATETIME2(3)
) AS s;
GO

INSERT INTO retail.online_orders (order_id, customer_id, order_ts, subtotal_amount, tax_amount, total_amount, payment_method, loaded_at)
SELECT order_id, customer_id, order_ts, subtotal_amount, tax_amount, total_amount, payment_method, loaded_at
FROM OPENROWSET(
    BULK 'oltp-export/online_orders.csv',
    DATA_SOURCE   = 'OltpBlobSrc',
    FORMAT        = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW      = 2,
    FIELDQUOTE    = '"'
) WITH (
        order_id                 VARCHAR(64),
        customer_id              BIGINT,
        order_ts                 DATETIME2(3),
        subtotal_amount          DECIMAL(19,4),
        tax_amount               DECIMAL(19,4),
        total_amount             DECIMAL(19,4),
        payment_method           VARCHAR(30),
        loaded_at                DATETIME2(3)
) AS s;
GO

INSERT INTO retail.online_order_lines (order_id, line_number, product_id, quantity, unit_price, extended_price, promo_code, fulfillment_mode, fulfillment_status, node_type, node_id, picked_ts, shipped_ts, delivered_ts, loaded_at)
SELECT order_id, line_number, product_id, quantity, unit_price, extended_price, promo_code, fulfillment_mode, fulfillment_status, node_type, node_id, picked_ts, shipped_ts, delivered_ts, loaded_at
FROM OPENROWSET(
    BULK 'oltp-export/online_order_lines.csv',
    DATA_SOURCE   = 'OltpBlobSrc',
    FORMAT        = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW      = 2,
    FIELDQUOTE    = '"'
) WITH (
        order_id                 VARCHAR(64),
        line_number              INT,
        product_id               BIGINT,
        quantity                 INT,
        unit_price               DECIMAL(19,4),
        extended_price           DECIMAL(19,4),
        promo_code               VARCHAR(40),
        fulfillment_mode         VARCHAR(30),
        fulfillment_status       VARCHAR(30),
        node_type                VARCHAR(30),
        node_id                  BIGINT,
        picked_ts                DATETIME2(3),
        shipped_ts               DATETIME2(3),
        delivered_ts             DATETIME2(3),
        loaded_at                DATETIME2(3)
) AS s;
GO

INSERT INTO retail.payments (receipt_id, order_id, payment_ts, payment_method, amount, transaction_id, status, decline_reason, processing_time_ms, store_id, customer_id, loaded_at)
SELECT receipt_id, order_id, payment_ts, payment_method, amount, transaction_id, status, decline_reason, processing_time_ms, store_id, customer_id, loaded_at
FROM OPENROWSET(
    BULK 'oltp-export/payments.csv',
    DATA_SOURCE   = 'OltpBlobSrc',
    FORMAT        = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW      = 2,
    FIELDQUOTE    = '"'
) WITH (
        receipt_id               VARCHAR(64),
        order_id                 VARCHAR(64),
        payment_ts               DATETIME2(3),
        payment_method           VARCHAR(30),
        amount                   DECIMAL(19,4),
        transaction_id           VARCHAR(64),
        status                   VARCHAR(20),
        decline_reason           VARCHAR(100),
        processing_time_ms       BIGINT,
        store_id                 BIGINT,
        customer_id              BIGINT,
        loaded_at                DATETIME2(3)
) AS s;
GO

INSERT INTO retail.inventory_transactions (location_type, store_id, dc_id, product_id, txn_ts, txn_type, quantity, balance, source, trace_id, loaded_at)
SELECT location_type, store_id, dc_id, product_id, txn_ts, txn_type, quantity, balance, source, trace_id, loaded_at
FROM OPENROWSET(
    BULK 'oltp-export/inventory_transactions.csv',
    DATA_SOURCE   = 'OltpBlobSrc',
    FORMAT        = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW      = 2,
    FIELDQUOTE    = '"'
) WITH (
        location_type            VARCHAR(10),
        store_id                 BIGINT,
        dc_id                    BIGINT,
        product_id               BIGINT,
        txn_ts                   DATETIME2(3),
        txn_type                 VARCHAR(30),
        quantity                 INT,
        balance                  INT,
        source                   VARCHAR(50),
        trace_id                 VARCHAR(64),
        loaded_at                DATETIME2(3)
) AS s;
GO

INSERT INTO retail.reorders (reorder_ts, store_id, dc_id, product_id, current_quantity, reorder_quantity, reorder_point, priority, trace_id, loaded_at)
SELECT reorder_ts, store_id, dc_id, product_id, current_quantity, reorder_quantity, reorder_point, priority, trace_id, loaded_at
FROM OPENROWSET(
    BULK 'oltp-export/reorders.csv',
    DATA_SOURCE   = 'OltpBlobSrc',
    FORMAT        = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW      = 2,
    FIELDQUOTE    = '"'
) WITH (
        reorder_ts               DATETIME2(3),
        store_id                 BIGINT,
        dc_id                    BIGINT,
        product_id               BIGINT,
        current_quantity         INT,
        reorder_quantity         INT,
        reorder_point            INT,
        priority                 VARCHAR(20),
        trace_id                 VARCHAR(64),
        loaded_at                DATETIME2(3)
) AS s;
GO

INSERT INTO retail.stockouts (stockout_ts, store_id, dc_id, product_id, last_known_quantity, trace_id, loaded_at)
SELECT stockout_ts, store_id, dc_id, product_id, last_known_quantity, trace_id, loaded_at
FROM OPENROWSET(
    BULK 'oltp-export/stockouts.csv',
    DATA_SOURCE   = 'OltpBlobSrc',
    FORMAT        = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW      = 2,
    FIELDQUOTE    = '"'
) WITH (
        stockout_ts              DATETIME2(3),
        store_id                 BIGINT,
        dc_id                    BIGINT,
        product_id               BIGINT,
        last_known_quantity      INT,
        trace_id                 VARCHAR(64),
        loaded_at                DATETIME2(3)
) AS s;
GO

INSERT INTO retail.shipment_movements (shipment_number, truck_id, dc_id, store_id, status, event_ts, eta, etd, departure_time, actual_unload_duration, trace_id, loaded_at)
SELECT shipment_number, truck_id, dc_id, store_id, status, event_ts, eta, etd, departure_time, actual_unload_duration, trace_id, loaded_at
FROM OPENROWSET(
    BULK 'oltp-export/shipment_movements.csv',
    DATA_SOURCE   = 'OltpBlobSrc',
    FORMAT        = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW      = 2,
    FIELDQUOTE    = '"'
) WITH (
        shipment_number          VARCHAR(64),
        truck_id                 BIGINT,
        dc_id                    BIGINT,
        store_id                 BIGINT,
        status                   VARCHAR(30),
        event_ts                 DATETIME2(3),
        eta                      DATETIME2(3),
        etd                      DATETIME2(3),
        departure_time           DATETIME2(3),
        actual_unload_duration   DECIMAL(9,2),
        trace_id                 VARCHAR(64),
        loaded_at                DATETIME2(3)
) AS s;
GO

INSERT INTO retail.shipment_lines (shipment_number, truck_id, product_id, quantity, action, location_id, location_type, event_ts, trace_id, loaded_at)
SELECT shipment_number, truck_id, product_id, quantity, action, location_id, location_type, event_ts, trace_id, loaded_at
FROM OPENROWSET(
    BULK 'oltp-export/shipment_lines.csv',
    DATA_SOURCE   = 'OltpBlobSrc',
    FORMAT        = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW      = 2,
    FIELDQUOTE    = '"'
) WITH (
        shipment_number          VARCHAR(64),
        truck_id                 BIGINT,
        product_id               BIGINT,
        quantity                 INT,
        action                   VARCHAR(20),
        location_id              BIGINT,
        location_type            VARCHAR(10),
        event_ts                 DATETIME2(3),
        trace_id                 VARCHAR(64),
        loaded_at                DATETIME2(3)
) AS s;
GO
