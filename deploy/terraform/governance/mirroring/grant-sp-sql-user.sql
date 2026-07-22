-- =============================================================================
-- Fabric Mirroring prerequisite: grant the source connection's service
-- principal access to the Azure SQL database being mirrored.
--
-- Run this ONCE against the source database (e.g. hallmarkerp) connected as an
-- Entra admin, BEFORE `terraform apply` creates the fabric_connection. The
-- connection's test step (skip_test_connection = false) authenticates as this
-- service principal, so the login must exist first.
--
-- Replace <SP_DISPLAY_NAME> with the Entra display name of the app registration
-- whose client id you pass as `mirror_sp_client_id`. CREATE USER ... FROM
-- EXTERNAL PROVIDER resolves the principal by display name in the server's
-- tenant.
--
-- Mirroring of Azure SQL Database requires the connecting principal to be able
-- to enable change tracking and read changes, so CONTROL on the database (or
-- db_owner) is the simplest sufficient grant for a demo. Tighten per the
-- Microsoft mirroring prerequisites for production.
-- https://learn.microsoft.com/fabric/mirroring/azure-sql-database-tutorial
-- =============================================================================

CREATE USER [<SP_DISPLAY_NAME>] FROM EXTERNAL PROVIDER;
GO

ALTER ROLE db_owner ADD MEMBER [<SP_DISPLAY_NAME>];
GO

-- Minimum-privilege alternative to db_owner (uncomment and grant instead):
-- ALTER ROLE db_datareader ADD MEMBER [<SP_DISPLAY_NAME>];
-- GRANT CONTROL TO [<SP_DISPLAY_NAME>];   -- required to manage change tracking
-- GO
