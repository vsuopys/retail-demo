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

The first code cell is tagged `parameters`, so every value below can be set as a
Fabric notebook/job **parameter** (or an environment variable). Derived values
(`JDBC_URL`, the `ONLY_TABLES` list, the batch `LOADED_AT`) are computed in the
cell immediately after, so injected overrides take effect. `AZURE_SQL_SERVER`
and `AZURE_SQL_DATABASE` must be supplied — the run asserts on them.

| Parameter | Default | Purpose |
| --- | --- | --- |
| `LAKEHOUSE_NAME` | `retail_lakehouse` | source lakehouse |
| `SILVER_DB` | `silver` | source schema |
| `AZURE_SQL_SERVER` | *(required)* | e.g. `myserver.database.windows.net` |
| `AZURE_SQL_DATABASE` | *(required)* | target database |
| `TARGET_SCHEMA` | `retail` | target schema |
| `AUTH_MODE` | `aad_token` | `aad_token` (workspace identity) or `sql` |
| `KEY_VAULT_URL` / `SQL_SECRET_NAME` | – | Key Vault-backed SQL password (SQL auth) |
| `WRITE_FORMAT` | `jdbc` | column-list INSERT (honors IDENTITY PKs + `loaded_at` default). See caveat below before using the BULK COPY connector |
| `BATCH_SIZE` | `100000` | insert batch size |
| `MAX_ROWS_PER_WRITE` | `1000000` | chunk size for AAD long-load token refresh + small-tier commit stability (0 disables) |
| `WRITE_PARTITIONS` | `8` | concurrent JDBC connections per write (0 = leave as-is) |
| `TRUNCATE_BEFORE_LOAD` | `true` | full-reload: clear targets first |
| `LOADED_AT` | *(run time)* | override the batch load timestamp (UTC `yyyy-mm-dd hh:mm:ss.fff`) |
| `ONLY_TABLES` | *(all)* | comma-separated subset of OLTP tables |

### Idempotency / reload

* Convert cents to dollars in-transform: `amount = cents / 100.0`.
* With `TRUNCATE_BEFORE_LOAD=true` the notebook drops the FK constraints
  (saving their definitions to `retail._fk_backup`), `TRUNCATE`s every target,
  loads, then recreates the FKs `WITH NOCHECK` (untrusted, no validation scan).
  `TRUNCATE` is used instead of `DELETE` because a plain delete on the 100M+ row
  fact tables is I/O-bound and can run for hours on this Azure SQL tier. Safe to
  re-run for a clean full reload.
* Business keys for future upsert work: `sales.receipt_id`,
  `online_orders.order_id`, `sale_lines (receipt_id, line_number)`,
  `online_order_lines (order_id, line_number)`.
* Event-grain tables (inventory, reorders, stockouts, shipment_*) have no
  natural key and are loaded append-only.
* `loaded_at` is stamped by the ETL with a single UTC batch timestamp computed
  once per run (all rows of a run share one value), so it marks the load batch
  rather than per-row insert time. Override with `LOADED_AT` for reproducible
  re-runs.

### Scale

`fact_receipt_lines` (~182M) and the inventory ledgers (~180M each) dominate
runtime. The notebook uses `WRITE_FORMAT=jdbc` (batched column-list INSERTs) so
that the server generates the `BIGINT IDENTITY` surrogate PKs and fills the
`loaded_at` default — columns the source DataFrames intentionally omit.

The MSSQL Spark connector (`com.microsoft.sqlserver.jdbc.spark`, BULK COPY) is
faster but does **not** work against this schema as-is: BULK COPY requires the
DataFrame to supply the full target column set, so it fails on the IDENTITY and
`loaded_at` columns (`NoSuchElementException: key not found: loaded_at`). Only
switch to it if you first extend the transforms to emit every non-default column.
Throughput on `jdbc` is driven by `BATCH_SIZE` and `WRITE_PARTITIONS`. More
partitions = more parallel connections, but too many overwhelm a small Azure SQL
tier: the parallel bulk inserts pile up on `LATCH_SH` and the server starts
dropping connections (`SQLServerException: The connection is closed`), aborting
the Spark job. `WRITE_PARTITIONS=8` is a safe default; raise it on larger vCore
tiers, lower it (e.g. `4`) if connections still drop.

### Resilience (connection drops and retries)

Two layers guard against transient connection drops:

* The JDBC URL sets `connectRetryCount`/`connectRetryInterval`, so the SQL Server
  driver transparently reconnects a broken idle connection, and raw connection
  opens (used for the reset/FK DDL) are retried with exponential backoff.
* Each table load is wrapped in a retry-with-backoff: on a transient write
  failure the target is `TRUNCATE`d and the write is retried. This is
  duplicate-safe because tables load in FK-safe (parent -> child) order with FK
  enforcement off, so nothing references the table being written yet. A blanket
  retry of the whole `save()` is intentionally **not** used — Spark commits
  per-partition, so re-running a partially-succeeded write would duplicate rows.

### Long loads and AAD token expiry

An AAD access token lives ~60-75 min. A **single** `write()` that runs longer
than that fails mid-load with `Login failed ... Token is expired`, because Spark
opens new executor connections throughout the write and any connection opened
after the token expires is rejected.

The notebook avoids this under `AUTH_MODE=aad_token` by splitting any table above
`MAX_ROWS_PER_WRITE` into deterministic hash chunks and **re-acquiring a fresh
token before each chunk**, so no single connection outlives its token. Chunks are
keyed by a row hash, so a source re-scan never duplicates or drops rows. The hashed
frame is persisted (`DISK_ONLY`) and materialized once, so each chunk reads from
cache instead of recomputing the (often expensive) source join per chunk. Tune
`MAX_ROWS_PER_WRITE` down if a chunk still approaches the token lifetime or if a
constrained Azure SQL tier drops the connection at chunk-commit under load — a
smaller chunk commits sooner and keeps the per-write pressure low (this is why the
default is a modest 1M rather than a multi-million-row chunk).

`AUTH_MODE=sql` (Key Vault password) has no token to expire and needs no
chunking — prefer it if SQL authentication is enabled on the server.

## Bulk load: silver -> blob CSV -> Azure SQL (faster alternative)

The row-by-row JDBC path above is resilient but slow for the 100M+ row fact
tables. A faster, set-based alternative stages the data as CSV in Azure Blob
Storage and loads it with `BULK INSERT`:

```
retail_lakehouse.silver.*  ->  <container>/<prefix>/<table>.csv  ->  retail.*
      (Delta)                  fabric/lakehouse/51-silver-to-blob-csv.ipynb
                               deploy/azuresql/bulk-load/10-bulk-load.sql
```

* **`fabric/lakehouse/51-silver-to-blob-csv.ipynb`** reshapes silver with the
  **exact same transforms as notebook 50** (imported verbatim, so the two never
  drift) and writes RFC4180 CSV to blob. Each file holds every OLTP column except
  the `IDENTITY` surrogate PK (the server assigns it on load), in DDL order with
  `loaded_at` last; `BIT` columns are emitted as `0`/`1`. Set `BLOB_ACCOUNT`,
  `BLOB_CONTAINER`, and optionally `BLOB_PREFIX` (default `oltp-export`),
  `ONLY_TABLES`, and `LOADED_AT`. `AUTH_METHOD` selects how Spark authenticates
  to the storage account: `aad` (default, uses the running user's AAD identity via
  Fabric passthrough — no secret needed, requires Storage Blob Data RBAC), `sas`
  (`BLOB_SAS`), or `key` (`BLOB_ACCOUNT_KEY`). AAD passthrough is required for
  HNS/ADLS Gen2 accounts that have shared-key access disabled.
* **`deploy/azuresql/bulk-load/10-bulk-load.sql`** creates the SAS-scoped
  `DATABASE SCOPED CREDENTIAL` + `EXTERNAL DATA SOURCE`, then for each table (in
  FK-safe order) bulk-loads the CSV into a `#stg_<table>` temp table via
  `BULK INSERT ... FROM '<table>.csv' WITH (FORMAT='CSV', ...)` and copies it into
  the real table with `INSERT ... SELECT` (so the `IDENTITY` surrogate PK is
  assigned by the server). Replace `__BLOB_URL__` (container URL) and
  `__SAS_TOKEN__` (read/list SAS, no leading `?`) before running. The staging
  column types and the CSV column order are both generated from
  `deploy/azuresql/schema/*.sql`, so they stay aligned.

Why `BULK INSERT` (not `OPENROWSET`): Azure SQL DB does not support
`OPENROWSET(BULK ...)` with a `WITH (schema)` clause for `FORMAT='CSV'` over an
`https://` data source — that is a Synapse serverless feature. `BULK INSERT` into
a staging temp table is the supported CSV path, and staging keeps IDENTITY PKs
intact.

Why blob (not OneLake): Azure SQL DB's bulk APIs can only read from Azure Blob
Storage via a SAS-scoped external data source — they cannot read OneLake (which
needs AAD).

**Scale note.** `SINGLE_FILE=True` (default) writes one `<table>.csv` per table —
simplest to load with the committed static SQL and ideal for testing a subset via
`ONLY_TABLES`. Azure SQL DB `BULK INSERT` reads **one file per statement**
(no wildcards), so for very large tables set `SINGLE_FILE=False` to write parallel
part files; the notebook's RUN cell then prints a generated per-file loader (one
`BULK INSERT` per part) to run after the setup section.

CSV caveat: `BULK INSERT` with `FORMAT='CSV'` does not reliably handle line breaks
embedded inside quoted text fields. The synthetic data does not contain them, but
keep it in mind if the source ever changes.
