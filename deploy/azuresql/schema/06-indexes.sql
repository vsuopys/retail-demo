/* =============================================================================
   retail-demo :: Azure SQL OLTP source schema
   06 - Secondary indexes
   -----------------------------------------------------------------------------
   Non-clustered indexes supporting the common OLTP access paths: FK lookups,
   header->line navigation, and time-range / business-key queries used by the
   downstream lakehouse ETL. All are idempotent.
   ============================================================================= */

/* ----- sales / sale_lines ------------------------------------------------ */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_sales_store_ts' AND object_id = OBJECT_ID(N'retail.sales'))
    CREATE INDEX IX_sales_store_ts ON retail.sales (store_id, sale_ts);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_sales_customer' AND object_id = OBJECT_ID(N'retail.sales'))
    CREATE INDEX IX_sales_customer ON retail.sales (customer_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_sales_sale_ts' AND object_id = OBJECT_ID(N'retail.sales'))
    CREATE INDEX IX_sales_sale_ts ON retail.sales (sale_ts);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_sale_lines_product' AND object_id = OBJECT_ID(N'retail.sale_lines'))
    CREATE INDEX IX_sale_lines_product ON retail.sale_lines (product_id);
GO

/* ----- online orders / lines --------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_online_orders_customer_ts' AND object_id = OBJECT_ID(N'retail.online_orders'))
    CREATE INDEX IX_online_orders_customer_ts ON retail.online_orders (customer_id, order_ts);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_online_orders_order_ts' AND object_id = OBJECT_ID(N'retail.online_orders'))
    CREATE INDEX IX_online_orders_order_ts ON retail.online_orders (order_ts);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_online_order_lines_product' AND object_id = OBJECT_ID(N'retail.online_order_lines'))
    CREATE INDEX IX_online_order_lines_product ON retail.online_order_lines (product_id);
GO

/* ----- payments ---------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_payments_receipt' AND object_id = OBJECT_ID(N'retail.payments'))
    CREATE INDEX IX_payments_receipt ON retail.payments (receipt_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_payments_order' AND object_id = OBJECT_ID(N'retail.payments'))
    CREATE INDEX IX_payments_order ON retail.payments (order_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_payments_ts' AND object_id = OBJECT_ID(N'retail.payments'))
    CREATE INDEX IX_payments_ts ON retail.payments (payment_ts);
GO
/* transaction_id is unique when present (NULL for e.g. cash) */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_payments_transaction' AND object_id = OBJECT_ID(N'retail.payments'))
    CREATE UNIQUE INDEX UX_payments_transaction ON retail.payments (transaction_id)
        WHERE transaction_id IS NOT NULL;
GO

/* ----- inventory_transactions -------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_inv_txn_store_product_ts' AND object_id = OBJECT_ID(N'retail.inventory_transactions'))
    CREATE INDEX IX_inv_txn_store_product_ts ON retail.inventory_transactions (store_id, product_id, txn_ts);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_inv_txn_dc_product_ts' AND object_id = OBJECT_ID(N'retail.inventory_transactions'))
    CREATE INDEX IX_inv_txn_dc_product_ts ON retail.inventory_transactions (dc_id, product_id, txn_ts);
GO

/* ----- reorders / stockouts ---------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_reorders_product_ts' AND object_id = OBJECT_ID(N'retail.reorders'))
    CREATE INDEX IX_reorders_product_ts ON retail.reorders (product_id, reorder_ts);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_stockouts_product_ts' AND object_id = OBJECT_ID(N'retail.stockouts'))
    CREATE INDEX IX_stockouts_product_ts ON retail.stockouts (product_id, stockout_ts);
GO

/* ----- shipments --------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ship_move_number' AND object_id = OBJECT_ID(N'retail.shipment_movements'))
    CREATE INDEX IX_ship_move_number ON retail.shipment_movements (shipment_number, event_ts);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ship_move_truck' AND object_id = OBJECT_ID(N'retail.shipment_movements'))
    CREATE INDEX IX_ship_move_truck ON retail.shipment_movements (truck_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ship_lines_number' AND object_id = OBJECT_ID(N'retail.shipment_lines'))
    CREATE INDEX IX_ship_lines_number ON retail.shipment_lines (shipment_number);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ship_lines_product' AND object_id = OBJECT_ID(N'retail.shipment_lines'))
    CREATE INDEX IX_ship_lines_product ON retail.shipment_lines (product_id);
GO
