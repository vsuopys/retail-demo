/* =============================================================================
   retail-demo :: Azure SQL OLTP source schema
   02 - Master / reference tables
   -----------------------------------------------------------------------------
   Natural BIGINT primary keys carried over from the lakehouse dimensions
   (dim_*.ID). These keys are the mirror/ETL join keys, e.g.
   retail.customers.customer_id == silver.dim_customers.ID.
   ============================================================================= */

/* ---------------------------------------------------------------------------
   geographies  <-  silver.dim_geographies
   --------------------------------------------------------------------------- */
IF OBJECT_ID(N'retail.geographies', N'U') IS NULL
BEGIN
    CREATE TABLE retail.geographies
    (
        geography_id   BIGINT        NOT NULL,
        city           NVARCHAR(100) NULL,
        state          NVARCHAR(50)  NULL,
        zip_code       VARCHAR(15)   NULL,
        district       NVARCHAR(100) NULL,
        region         NVARCHAR(100) NULL,
        loaded_at      DATETIME2(3)  NOT NULL CONSTRAINT DF_geographies_loaded_at DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_geographies PRIMARY KEY CLUSTERED (geography_id)
    );
END;
GO

/* ---------------------------------------------------------------------------
   customers  <-  silver.dim_customers
   --------------------------------------------------------------------------- */
IF OBJECT_ID(N'retail.customers', N'U') IS NULL
BEGIN
    CREATE TABLE retail.customers
    (
        customer_id    BIGINT        NOT NULL,
        first_name     NVARCHAR(100) NULL,
        last_name      NVARCHAR(100) NULL,
        address        NVARCHAR(255) NULL,
        geography_id   BIGINT        NULL,
        loyalty_card   VARCHAR(50)   NULL,
        phone          VARCHAR(30)   NULL,
        ble_id         VARCHAR(64)   NULL,
        ad_id          VARCHAR(64)   NULL,
        loaded_at      DATETIME2(3)  NOT NULL CONSTRAINT DF_customers_loaded_at DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_customers PRIMARY KEY CLUSTERED (customer_id)
    );
END;
GO

/* ---------------------------------------------------------------------------
   stores  <-  silver.dim_stores
   --------------------------------------------------------------------------- */
IF OBJECT_ID(N'retail.stores', N'U') IS NULL
BEGIN
    CREATE TABLE retail.stores
    (
        store_id                    BIGINT        NOT NULL,
        store_number                VARCHAR(20)   NULL,
        address                     NVARCHAR(255) NULL,
        geography_id                BIGINT        NULL,
        tax_rate                    DECIMAL(6, 4) NULL,
        volume_class                VARCHAR(20)   NULL,
        store_format                VARCHAR(30)   NULL,
        operating_hours             VARCHAR(50)   NULL,
        daily_traffic_multiplier    DECIMAL(9, 4) NULL,
        loaded_at                   DATETIME2(3)  NOT NULL CONSTRAINT DF_stores_loaded_at DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_stores PRIMARY KEY CLUSTERED (store_id)
    );
END;
GO

/* ---------------------------------------------------------------------------
   distribution_centers  <-  silver.dim_distribution_centers
   --------------------------------------------------------------------------- */
IF OBJECT_ID(N'retail.distribution_centers', N'U') IS NULL
BEGIN
    CREATE TABLE retail.distribution_centers
    (
        dc_id          BIGINT        NOT NULL,
        dc_number      VARCHAR(20)   NULL,
        address        NVARCHAR(255) NULL,
        geography_id   BIGINT        NULL,
        loaded_at      DATETIME2(3)  NOT NULL CONSTRAINT DF_dc_loaded_at DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_distribution_centers PRIMARY KEY CLUSTERED (dc_id)
    );
END;
GO

/* ---------------------------------------------------------------------------
   trucks  <-  silver.dim_trucks   (DCID is nullable for pool trucks)
   --------------------------------------------------------------------------- */
IF OBJECT_ID(N'retail.trucks', N'U') IS NULL
BEGIN
    CREATE TABLE retail.trucks
    (
        truck_id       BIGINT        NOT NULL,
        license_plate  VARCHAR(20)   NULL,
        refrigeration  BIT           NULL,
        dc_id          BIGINT        NULL,
        loaded_at      DATETIME2(3)  NOT NULL CONSTRAINT DF_trucks_loaded_at DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_trucks PRIMARY KEY CLUSTERED (truck_id)
    );
END;
GO

/* ---------------------------------------------------------------------------
   products  <-  silver.dim_products
   --------------------------------------------------------------------------- */
IF OBJECT_ID(N'retail.products', N'U') IS NULL
BEGIN
    CREATE TABLE retail.products
    (
        product_id              BIGINT         NOT NULL,
        product_name            NVARCHAR(200)  NULL,
        brand                   NVARCHAR(100)  NULL,
        company                 NVARCHAR(100)  NULL,
        department              NVARCHAR(100)  NULL,
        category                NVARCHAR(100)  NULL,
        subcategory             NVARCHAR(100)  NULL,
        cost                    DECIMAL(19, 4) NULL,
        msrp                    DECIMAL(19, 4) NULL,
        sale_price              DECIMAL(19, 4) NULL,
        requires_refrigeration  BIT            NULL,
        launch_date             DATETIME2(3)   NULL,
        taxability              VARCHAR(30)    NULL,
        tags                    NVARCHAR(500)  NULL,
        loaded_at               DATETIME2(3)   NOT NULL CONSTRAINT DF_products_loaded_at DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_products PRIMARY KEY CLUSTERED (product_id)
    );
END;
GO
