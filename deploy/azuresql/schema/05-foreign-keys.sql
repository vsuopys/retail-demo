/* =============================================================================
   retail-demo :: Azure SQL OLTP source schema
   05 - Foreign keys
   -----------------------------------------------------------------------------
   Referential integrity between transaction tables and master/reference tables,
   and between headers and their lines. Polymorphic links (e.g.
   shipment_lines.location_id, which may point at a store or a DC) are left
   without FKs by design.

   FKs referencing a business key (receipt_id / order_id) target the UNIQUE
   constraints defined in 03-commerce-tables.sql.
   ============================================================================= */

/* ----- master -> geographies / dc ---------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_customers_geography')
    ALTER TABLE retail.customers ADD CONSTRAINT FK_customers_geography
        FOREIGN KEY (geography_id) REFERENCES retail.geographies (geography_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_stores_geography')
    ALTER TABLE retail.stores ADD CONSTRAINT FK_stores_geography
        FOREIGN KEY (geography_id) REFERENCES retail.geographies (geography_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_dc_geography')
    ALTER TABLE retail.distribution_centers ADD CONSTRAINT FK_dc_geography
        FOREIGN KEY (geography_id) REFERENCES retail.geographies (geography_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_trucks_dc')
    ALTER TABLE retail.trucks ADD CONSTRAINT FK_trucks_dc
        FOREIGN KEY (dc_id) REFERENCES retail.distribution_centers (dc_id);
GO

/* ----- sales / sale_lines ------------------------------------------------ */
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_sales_store')
    ALTER TABLE retail.sales ADD CONSTRAINT FK_sales_store
        FOREIGN KEY (store_id) REFERENCES retail.stores (store_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_sales_customer')
    ALTER TABLE retail.sales ADD CONSTRAINT FK_sales_customer
        FOREIGN KEY (customer_id) REFERENCES retail.customers (customer_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_sale_lines_sale')
    ALTER TABLE retail.sale_lines ADD CONSTRAINT FK_sale_lines_sale
        FOREIGN KEY (receipt_id) REFERENCES retail.sales (receipt_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_sale_lines_product')
    ALTER TABLE retail.sale_lines ADD CONSTRAINT FK_sale_lines_product
        FOREIGN KEY (product_id) REFERENCES retail.products (product_id);
GO

/* ----- online orders / lines --------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_online_orders_customer')
    ALTER TABLE retail.online_orders ADD CONSTRAINT FK_online_orders_customer
        FOREIGN KEY (customer_id) REFERENCES retail.customers (customer_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_online_order_lines_order')
    ALTER TABLE retail.online_order_lines ADD CONSTRAINT FK_online_order_lines_order
        FOREIGN KEY (order_id) REFERENCES retail.online_orders (order_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_online_order_lines_product')
    ALTER TABLE retail.online_order_lines ADD CONSTRAINT FK_online_order_lines_product
        FOREIGN KEY (product_id) REFERENCES retail.products (product_id);
GO

/* ----- payments ---------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_payments_sale')
    ALTER TABLE retail.payments ADD CONSTRAINT FK_payments_sale
        FOREIGN KEY (receipt_id) REFERENCES retail.sales (receipt_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_payments_order')
    ALTER TABLE retail.payments ADD CONSTRAINT FK_payments_order
        FOREIGN KEY (order_id) REFERENCES retail.online_orders (order_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_payments_store')
    ALTER TABLE retail.payments ADD CONSTRAINT FK_payments_store
        FOREIGN KEY (store_id) REFERENCES retail.stores (store_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_payments_customer')
    ALTER TABLE retail.payments ADD CONSTRAINT FK_payments_customer
        FOREIGN KEY (customer_id) REFERENCES retail.customers (customer_id);
GO

/* ----- inventory_transactions -------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_inv_txn_store')
    ALTER TABLE retail.inventory_transactions ADD CONSTRAINT FK_inv_txn_store
        FOREIGN KEY (store_id) REFERENCES retail.stores (store_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_inv_txn_dc')
    ALTER TABLE retail.inventory_transactions ADD CONSTRAINT FK_inv_txn_dc
        FOREIGN KEY (dc_id) REFERENCES retail.distribution_centers (dc_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_inv_txn_product')
    ALTER TABLE retail.inventory_transactions ADD CONSTRAINT FK_inv_txn_product
        FOREIGN KEY (product_id) REFERENCES retail.products (product_id);
GO

/* ----- reorders ---------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_reorders_store')
    ALTER TABLE retail.reorders ADD CONSTRAINT FK_reorders_store
        FOREIGN KEY (store_id) REFERENCES retail.stores (store_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_reorders_dc')
    ALTER TABLE retail.reorders ADD CONSTRAINT FK_reorders_dc
        FOREIGN KEY (dc_id) REFERENCES retail.distribution_centers (dc_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_reorders_product')
    ALTER TABLE retail.reorders ADD CONSTRAINT FK_reorders_product
        FOREIGN KEY (product_id) REFERENCES retail.products (product_id);
GO

/* ----- stockouts --------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_stockouts_store')
    ALTER TABLE retail.stockouts ADD CONSTRAINT FK_stockouts_store
        FOREIGN KEY (store_id) REFERENCES retail.stores (store_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_stockouts_dc')
    ALTER TABLE retail.stockouts ADD CONSTRAINT FK_stockouts_dc
        FOREIGN KEY (dc_id) REFERENCES retail.distribution_centers (dc_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_stockouts_product')
    ALTER TABLE retail.stockouts ADD CONSTRAINT FK_stockouts_product
        FOREIGN KEY (product_id) REFERENCES retail.products (product_id);
GO

/* ----- shipment movements / lines ---------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_ship_move_truck')
    ALTER TABLE retail.shipment_movements ADD CONSTRAINT FK_ship_move_truck
        FOREIGN KEY (truck_id) REFERENCES retail.trucks (truck_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_ship_move_dc')
    ALTER TABLE retail.shipment_movements ADD CONSTRAINT FK_ship_move_dc
        FOREIGN KEY (dc_id) REFERENCES retail.distribution_centers (dc_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_ship_move_store')
    ALTER TABLE retail.shipment_movements ADD CONSTRAINT FK_ship_move_store
        FOREIGN KEY (store_id) REFERENCES retail.stores (store_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_ship_lines_truck')
    ALTER TABLE retail.shipment_lines ADD CONSTRAINT FK_ship_lines_truck
        FOREIGN KEY (truck_id) REFERENCES retail.trucks (truck_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_ship_lines_product')
    ALTER TABLE retail.shipment_lines ADD CONSTRAINT FK_ship_lines_product
        FOREIGN KEY (product_id) REFERENCES retail.products (product_id);
GO
