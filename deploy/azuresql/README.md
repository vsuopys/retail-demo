# Azure SQL transactional (OLTP) source schema

A denormalized, transaction-oriented schema reverse-engineered from the
`retail_lakehouse` **silver** layer
(`utility/src/retail_setup/generation/schemas.py`). It is designed to be
deployed to **Azure SQL Database / Managed Instance** as an operational source
system and later **mirrored into the Fabric lakehouse `bronze` schema**.

This is intentionally **not** a star schema — there are no fact/dimension
tables. Instead it models the business as natural OLTP entities: master
reference data plus header/line transaction tables.

## Design decisions

| Decision | Choice |
| --- | --- |
| Structure | Master/reference tables + denormalized transaction tables with FKs |
| Money | `DECIMAL(19,4)` dollars (lakehouse `*_cents` are divided by 100 in ETL) |
| Scope | Core commerce + supply chain (IoT/sensor telemetry excluded) |
| Timestamps | `DATETIME2(3)`, UTC (matches lakehouse `event_ts`) |
| Primary keys | Master: natural `BIGINT` id from the dims. Transactions: `BIGINT IDENTITY` surrogate + `UNIQUE` business key |
| Mirroring | Every table has a primary key (required by Fabric mirroring) |

## Deploy order

Scripts are numbered and idempotent (safe to re-run):

1. `schema/01-create-schema.sql` — `retail` schema container
2. `schema/02-master-tables.sql` — geographies, customers, stores, distribution_centers, trucks, products
3. `schema/03-commerce-tables.sql` — sales, sale_lines, online_orders, online_order_lines, payments
4. `schema/04-supply-chain-tables.sql` — inventory_transactions, reorders, stockouts, shipment_movements, shipment_lines
5. `schema/05-foreign-keys.sql` — referential integrity
6. `schema/06-indexes.sql` — secondary indexes

Deploy with `sqlcmd` (or `Invoke-Sqlcmd`), or run the helper:

```powershell
./deploy-schema.ps1 -ServerName myserver.database.windows.net -DatabaseName retaildb
```

The helper uses Azure AD interactive auth by default; pass `-SqlUser` / `-SqlPassword`
for SQL auth.

## Lakehouse -> OLTP table map

| OLTP table | Source silver table(s) | Notes |
| --- | --- | --- |
| `retail.geographies` | `dim_geographies` | reference |
| `retail.customers` | `dim_customers` | reference; `customer_id = dim_customers.ID` |
| `retail.stores` | `dim_stores` | reference |
| `retail.distribution_centers` | `dim_distribution_centers` | reference |
| `retail.trucks` | `dim_trucks` | reference; `dc_id` nullable (pool trucks) |
| `retail.products` | `dim_products` | reference |
| `retail.sales` | `fact_receipts` (+ `fact_promotions`) | POS header; receipt-level promo folded onto header |
| `retail.sale_lines` | `fact_receipt_lines` (+ `fact_promo_lines`) | line-level promo discount folded onto line |
| `retail.online_orders` | `fact_online_order_headers` | |
| `retail.online_order_lines` | `fact_online_order_lines` | fulfillment fields retained |
| `retail.payments` | `fact_payments` | settles a POS receipt or an online order |
| `retail.inventory_transactions` | `fact_store_inventory_txn` + `fact_dc_inventory_txn` | unified via `location_type` (STORE/DC) |
| `retail.reorders` | `fact_reorders` | replenishment triggers |
| `retail.stockouts` | `fact_stockouts` | `StoreID`/`DCID` doubles -> `BIGINT` |
| `retail.shipment_movements` | `fact_truck_moves` | one row per shipment status event |
| `retail.shipment_lines` | `fact_truck_inventory` | truck load/unload actions |

### Excluded (out of scope for this OLTP model)

* IoT/sensor telemetry: `fact_foot_traffic`, `fact_ble_pings`,
  `fact_customer_zone_changes`, `fact_store_ops`, `fact_marketing`
* Gold aggregates (`sales_minute_store`, `top_products_15m`, ...) — these are
  analytical rollups, not source transactions.

## Denormalizations applied

* **Promotions folded in.** `fact_promotions` (receipt-level) collapses to
  `sales.promo_code`; `fact_promo_lines` (line-level) collapses to
  `sale_lines.promo_code` + `sale_lines.discount_amount`.
* **Inventory unified.** Store and DC inventory ledgers are one
  `inventory_transactions` table discriminated by `location_type`.
* **Amounts materialized.** The lakehouse keeps parallel `*_cents` integers and
  legacy string amounts; here a single `DECIMAL(19,4)` per amount is kept.

## ETL: silver -> Azure SQL

The reverse-ETL that seeds this schema from the lakehouse silver layer is the
Fabric PySpark notebook
[`fabric/lakehouse/50-silver-to-azuresql-oltp.ipynb`](../../fabric/lakehouse/50-silver-to-azuresql-oltp.ipynb).

It reads each silver Delta table, reshapes it to the OLTP model (renames,
`cents -> DECIMAL(19,4)`, unions store+DC inventory, folds promotions), and
bulk-writes to Azure SQL in **foreign-key-safe order**.

### Parameters (env vars / notebook parameters)

| Parameter | Default | Purpose |
| --- | --- | --- |
| `LAKEHOUSE_NAME` | `retail_lakehouse` | source lakehouse |
| `SILVER_DB` | `silver` | source schema |
| `AZURE_SQL_SERVER` | *(required)* | e.g. `myserver.database.windows.net` |
| `AZURE_SQL_DATABASE` | *(required)* | target database |
| `TARGET_SCHEMA` | `retail` | target schema |
| `AUTH_MODE` | `aad_token` | `aad_token` (workspace identity) or `sql` |
| `KEY_VAULT_URL` / `SQL_SECRET_NAME` | – | Key Vault-backed SQL password (SQL auth) |
| `WRITE_FORMAT` | `jdbc` | `jdbc`, or `com.microsoft.sqlserver.jdbc.spark` (BULK COPY) |
| `BATCH_SIZE` | `10000` | JDBC insert batch size |
| `TRUNCATE_BEFORE_LOAD` | `true` | full-reload: clear targets first |
| `ONLY_TABLES` | *(all)* | comma-separated subset of OLTP tables |

### Idempotency / reload

* Convert cents to dollars in-transform: `amount = cents / 100.0`.
* With `TRUNCATE_BEFORE_LOAD=true` the notebook disables FK enforcement,
  `DELETE`s all targets (child -> parent), loads, then re-enables the FKs. Safe
  to re-run for a clean full reload.
* Business keys for future upsert work: `sales.receipt_id`,
  `online_orders.order_id`, `sale_lines (receipt_id, line_number)`,
  `online_order_lines (order_id, line_number)`.
* Event-grain tables (inventory, reorders, stockouts, shipment_*) have no
  natural key and are loaded append-only.

### Scale

`fact_receipt_lines` (~182M) and the inventory ledgers (~180M each) dominate
runtime. For large loads set `WRITE_FORMAT=com.microsoft.sqlserver.jdbc.spark`
to use the MSSQL Spark connector's BULK COPY path (10-100x faster than generic
JDBC) when the connector is available on the Spark pool.
