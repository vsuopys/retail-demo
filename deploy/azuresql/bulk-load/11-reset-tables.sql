/* =============================================================================
   retail-demo :: reset retail.* OLTP tables for a clean bulk reload
   -----------------------------------------------------------------------------
   TRUNCATE is minimally logged and near-instant, so it is the right reset for the
   100M+ row fact tables (a DELETE would take far longer and bloat the log). But
   SQL Server refuses to TRUNCATE any table that is referenced by a FOREIGN KEY --
   even a disabled one -- so this script:

     1. drops every foreign key defined on a retail.* table,
     2. truncates all 16 tables,
     3. leaves the FKs dropped.

   AFTER loading data, restore referential integrity by re-running:
       deploy/azuresql/schema/05-foreign-keys.sql

   Recommended full-refresh sequence:
       11-reset-tables.sql                     (this script)
       <run notebook 51 to export all CSVs>
       10-bulk-load.sql                        (setup + BULK INSERT loads)
       ../schema/05-foreign-keys.sql           (recreate + validate FKs)

   Loading with the FKs dropped is also faster (no per-row constraint check); the
   final 05-foreign-keys.sql WITH CHECK re-validates every row once, in bulk.
   ============================================================================= */

SET NOCOUNT ON;
SET XACT_ABORT ON;

-------------------------------------------------------------------------------
-- 1. Drop every foreign key defined on a retail.* table (dynamic, name-agnostic)
-------------------------------------------------------------------------------
DECLARE @drop NVARCHAR(MAX) = N'';

SELECT @drop += N'ALTER TABLE '
    + QUOTENAME(SCHEMA_NAME(fk.schema_id)) + N'.'
    + QUOTENAME(OBJECT_NAME(fk.parent_object_id))
    + N' DROP CONSTRAINT ' + QUOTENAME(fk.name) + N';' + CHAR(10)
FROM sys.foreign_keys AS fk
WHERE SCHEMA_NAME(fk.schema_id) = N'retail';

IF LEN(@drop) > 0
BEGIN
    PRINT 'Dropping foreign keys:';
    PRINT @drop;
    EXEC sys.sp_executesql @drop;
END
ELSE
    PRINT 'No retail.* foreign keys found (already dropped).';
GO

-------------------------------------------------------------------------------
-- 2. Truncate all tables (order is irrelevant once the FKs are gone)
-------------------------------------------------------------------------------
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
GO

PRINT 'All retail.* tables truncated; foreign keys dropped.';
PRINT 'Load data (10-bulk-load.sql), then run ../schema/05-foreign-keys.sql to restore FKs.';
GO
