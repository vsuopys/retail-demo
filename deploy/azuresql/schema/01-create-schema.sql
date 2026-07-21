/* =============================================================================
   retail-demo :: Azure SQL transactional (OLTP) source schema
   01 - Schema container
   -----------------------------------------------------------------------------
   Reverse-engineered from the retail_lakehouse *silver* layer
   (utility/src/retail_setup/generation/schemas.py). This is a denormalized
   OLTP model (no facts/dimensions) intended to be deployed to Azure SQL
   Database / Managed Instance and later mirrored into the Fabric lakehouse
   `bronze` schema.

   Deploy order:
     01-create-schema.sql
     02-master-tables.sql
     03-commerce-tables.sql
     04-supply-chain-tables.sql
     05-foreign-keys.sql
     06-indexes.sql

   All scripts are idempotent (safe to re-run).
   ============================================================================= */

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'retail')
    EXEC (N'CREATE SCHEMA retail AUTHORIZATION dbo');
GO
