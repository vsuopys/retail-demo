/* =============================================================================
   retail-demo :: Azure SQL OLTP source schema
   04 - Supply-chain transaction tables
   -----------------------------------------------------------------------------
     * inventory_transactions  <- fact_store_inventory_txn + fact_dc_inventory_txn
                                   (unified via location_type STORE|DC)
     * reorders                <- fact_reorders
     * stockouts               <- fact_stockouts
     * shipment_movements      <- fact_truck_moves   (one row per status event)
     * shipment_lines          <- fact_truck_inventory (load/unload actions)
   ============================================================================= */

/* ---------------------------------------------------------------------------
   inventory_transactions  <-  fact_store_inventory_txn (+) fact_dc_inventory_txn
     Two lakehouse fact tables are unioned into one denormalized ledger.
     location_type discriminates STORE vs DC; exactly one of store_id / dc_id
     is populated.
   --------------------------------------------------------------------------- */
IF OBJECT_ID(N'retail.inventory_transactions', N'U') IS NULL
BEGIN
    CREATE TABLE retail.inventory_transactions
    (
        inventory_txn_id  BIGINT       IDENTITY(1, 1) NOT NULL,
        location_type     VARCHAR(10)  NOT NULL,      -- 'STORE' | 'DC'
        store_id          BIGINT       NULL,
        dc_id             BIGINT       NULL,
        product_id        BIGINT       NOT NULL,
        txn_ts            DATETIME2(3) NOT NULL,       -- event_ts (UTC)
        txn_type          VARCHAR(30)  NULL,
        quantity          INT          NULL,           -- signed movement
        balance           INT          NULL,           -- on-hand after txn
        source            VARCHAR(50)  NULL,
        trace_id          VARCHAR(64)  NULL,
        loaded_at         DATETIME2(3) NOT NULL CONSTRAINT DF_inv_txn_loaded_at DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_inventory_transactions PRIMARY KEY CLUSTERED (inventory_txn_id),
        CONSTRAINT CK_inv_txn_location_type CHECK (location_type IN ('STORE', 'DC')),
        CONSTRAINT CK_inv_txn_location CHECK
        (
            (location_type = 'STORE' AND store_id IS NOT NULL AND dc_id IS NULL)
         OR (location_type = 'DC'    AND dc_id    IS NOT NULL AND store_id IS NULL)
        )
    );
END;
GO

/* ---------------------------------------------------------------------------
   reorders  <-  fact_reorders   (replenishment trigger events)
   --------------------------------------------------------------------------- */
IF OBJECT_ID(N'retail.reorders', N'U') IS NULL
BEGIN
    CREATE TABLE retail.reorders
    (
        reorder_id         BIGINT       IDENTITY(1, 1) NOT NULL,
        reorder_ts         DATETIME2(3) NOT NULL,      -- event_ts (UTC)
        store_id           BIGINT       NULL,
        dc_id              BIGINT       NULL,
        product_id         BIGINT       NOT NULL,
        current_quantity   INT          NULL,
        reorder_quantity   INT          NULL,
        reorder_point      INT          NULL,
        priority           VARCHAR(20)  NULL,
        trace_id           VARCHAR(64)  NULL,
        loaded_at          DATETIME2(3) NOT NULL CONSTRAINT DF_reorders_loaded_at DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_reorders PRIMARY KEY CLUSTERED (reorder_id)
    );
END;
GO

/* ---------------------------------------------------------------------------
   stockouts  <-  fact_stockouts
     lakehouse StoreID / DCID are doubles (nullable); stored here as BIGINT.
   --------------------------------------------------------------------------- */
IF OBJECT_ID(N'retail.stockouts', N'U') IS NULL
BEGIN
    CREATE TABLE retail.stockouts
    (
        stockout_id          BIGINT       IDENTITY(1, 1) NOT NULL,
        stockout_ts          DATETIME2(3) NOT NULL,     -- event_ts (UTC)
        store_id             BIGINT       NULL,         -- fact_stockouts.StoreID
        dc_id                BIGINT       NULL,         -- fact_stockouts.DCID
        product_id           BIGINT       NOT NULL,     -- fact_stockouts.ProductID
        last_known_quantity  INT          NULL,         -- fact_stockouts.LastKnownQuantity
        trace_id             VARCHAR(64)  NULL,
        loaded_at            DATETIME2(3) NOT NULL CONSTRAINT DF_stockouts_loaded_at DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_stockouts PRIMARY KEY CLUSTERED (stockout_id)
    );
END;
GO

/* ---------------------------------------------------------------------------
   shipment_movements  <-  fact_truck_moves
     One row per shipment status event (departed / in-transit / arrived / ...).
     shipment_number is the lakehouse shipment_id business key (not unique here
     because a shipment emits multiple status rows).
   --------------------------------------------------------------------------- */
IF OBJECT_ID(N'retail.shipment_movements', N'U') IS NULL
BEGIN
    CREATE TABLE retail.shipment_movements
    (
        shipment_movement_id     BIGINT        IDENTITY(1, 1) NOT NULL,
        shipment_number          VARCHAR(64)   NOT NULL,   -- fact_truck_moves.shipment_id
        truck_id                 BIGINT        NULL,
        dc_id                    BIGINT        NULL,
        store_id                 BIGINT        NULL,
        status                   VARCHAR(30)   NULL,
        event_ts                 DATETIME2(3)  NOT NULL,   -- UTC
        eta                      DATETIME2(3)  NULL,
        etd                      DATETIME2(3)  NULL,
        departure_time           DATETIME2(3)  NULL,
        actual_unload_duration   DECIMAL(9, 2) NULL,       -- minutes
        trace_id                 VARCHAR(64)   NULL,
        loaded_at                DATETIME2(3)  NOT NULL CONSTRAINT DF_ship_move_loaded_at DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_shipment_movements PRIMARY KEY CLUSTERED (shipment_movement_id)
    );
END;
GO

/* ---------------------------------------------------------------------------
   shipment_lines  <-  fact_truck_inventory
     Truck load / unload actions for a shipment.
   --------------------------------------------------------------------------- */
IF OBJECT_ID(N'retail.shipment_lines', N'U') IS NULL
BEGIN
    CREATE TABLE retail.shipment_lines
    (
        shipment_line_id   BIGINT        IDENTITY(1, 1) NOT NULL,
        shipment_number    VARCHAR(64)   NOT NULL,   -- fact_truck_inventory.shipment_id
        truck_id           BIGINT        NULL,
        product_id         BIGINT        NOT NULL,
        quantity           INT           NULL,
        action             VARCHAR(20)   NULL,       -- LOAD | UNLOAD
        location_id        BIGINT        NULL,
        location_type      VARCHAR(10)   NULL,       -- STORE | DC
        event_ts           DATETIME2(3)  NOT NULL,   -- UTC
        trace_id           VARCHAR(64)   NULL,
        loaded_at          DATETIME2(3)  NOT NULL CONSTRAINT DF_ship_lines_loaded_at DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_shipment_lines PRIMARY KEY CLUSTERED (shipment_line_id)
    );
END;
GO
