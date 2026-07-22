# Governance migration runbook

Phase 3 of the governance re-architecture: split the single `retail-demo-dev`
workspace / `retail_lakehouse` into the per-layer medallion topology described in
[Governance topology](governance-topology.md). It honours the locked decisions
**D1** (dev/test/prod; dev first), **D2** (each layer physically owns its curated
tables), **D3** (single shared capacity `fabricdemovvs` + per-workspace
chargeback), and **D4** (Power BI App audiences for reporting).

The workspaces, lakehouses, Entra groups, domain, and RBAC that this runbook
targets are provisioned by
[`deploy/terraform/governance/`](https://github.com/amattas/retail-demo/blob/main/deploy/terraform/governance/);
the machine-readable topology lives in
[`deploy/config/topology.yml`](https://github.com/amattas/retail-demo/blob/main/deploy/config/topology.yml).

!!! danger "Immutability contract (non-negotiable)"
    The existing workspace `retail-demo-dev` and its `retail_lakehouse` are
    **immutable**. Every step here that touches them is **read-only** — nothing
    writes to, re-points, reconfigures, or deletes them. The one-off data copy
    (Track 3b) is **explicitly not part of IaC/fabric-cicd**. A clean deploy
    (Track 3a) **generates** data with the `retail-setup` utility and never
    references `retail-demo-dev`. Retiring the old workspace is a **separate,
    manual, human decision** made only after side-by-side validation.

## Target topology and item ownership (dev)

| Workspace | Owns | Physically owns |
| --- | --- | --- |
| `retail-bronze-dev` | `bronze_lh`, Eventhouses `retail_eventhouse` + `clickstream_eventhouse`, ingestion pipelines, stream-events notebook | raw landing + streaming event tables |
| `retail-silver-dev` | `silver_lh`, silver transform notebooks | **25 silver tables** (7 dims + 18 facts); shortcuts → bronze |
| `retail-gold-dev` | `gold_lh`, Direct Lake model `retail_model`, data agent, dashboards, gold pipelines | **13 gold tables** (9 aggregates + 4 ML outputs); shortcuts → silver |
| `retail-ds-sandbox-dev` | `ds_lh`, ML/experimentation notebooks | own experiment tables; read-only shortcuts → silver + gold |

The authoritative table inventory is
[`utility/src/retail_setup/generation/schemas.py`](https://github.com/amattas/retail-demo/blob/main/utility/src/retail_setup/generation/schemas.py)
(`TABLES`). The 4 ML gold tables (`churn_predictions`, `customer_segments`,
`demand_forecast`, `stockout_risk`) are produced by the `fabric/lakehouse/08–14`
ML notebooks, not the generator, but are bound in the semantic model with
`schemaName: gold`.

!!! note "Semantic-model single-bind"
    All **38** table TMDLs under
    `fabric/powerbi/retail_model.SemanticModel/definition/tables/` share **one**
    `expressionSource: 'DirectLake - retail_lakehouse'` (25 partitions use
    `schemaName: silver`, 13 use `schemaName: gold`). The Direct Lake model is
    therefore rebound by editing a **single** expression (see
    [Semantic-model rebind](#semantic-model-rebind)) — provided `gold_lh`
    surfaces both `gold.*` (owned) and `silver.*` (shortcut) schemas.

## Two migration tracks

The migration is expressed as two independent tracks. **Track 3a is the
canonical, repeatable path**; Track 3b is an optional one-off convenience.

### Track 3a — Repeatable clean deploy (IaC + generator)

The canonical path. It must succeed with `retail-demo-dev` **absent**.

1. **Provision empty per-layer items** via Terraform + fabric-cicd: create the
   four workspaces, assign the `Retail` domain, apply the RBAC matrix, attach
   capacity `fabricdemovvs`, and deploy **empty** items per layer (bronze:
   lakehouse + Eventhouses + ingestion + stream notebook; silver: lakehouse +
   transforms; gold: lakehouse + semantic model + data agent + dashboards; ds:
   lakehouse + ML notebooks).
2. **Generate data fresh** by running `retail-setup` once per data-bearing layer,
   each with its own workspace/lakehouse config and the **same `SEED`** for
   reproducibility:

   ```powershell
   # Silver: 25 dims+facts into retail-silver-dev / silver_lh
   retail-setup configure --env dev-silver --workspace-name retail-silver-dev --lakehouse-name silver_lh
   retail-setup render    --env dev-silver
   retail-setup deploy    --env dev-silver --skip-terraform   # items already provisioned

   # Gold: 9 aggregates into retail-gold-dev / gold_lh
   retail-setup configure --env dev-gold --workspace-name retail-gold-dev --lakehouse-name gold_lh
   retail-setup render    --env dev-gold
   retail-setup deploy    --env dev-gold --skip-terraform
   ```

3. Run the `fabric/lakehouse/08–14` ML notebooks against `gold_lh` (after silver
   exists) to populate the 4 ML gold tables.
4. Build the cross-layer OneLake shortcuts ([below](#shortcut-wiring)), rebind
   the semantic model ([below](#semantic-model-rebind)), re-ground the data agent
   ([below](#data-agent-re-grounding)), then run the [validation
   gates](#validation-gates).

`retail-setup` targeting is already parameterized: `retail-setup configure`
writes `workspace.name` / `lakehouse.name` into the deploy config, and the
environment overlay wins over the base file. See the open item on multi-workspace
config below.

### Track 3b — One-off copy of existing data (NOT IaC)

Use **only** if the team wants to preserve the *exact existing* `retail-demo-dev`
data instead of regenerating. It is a standalone procedure that lives **outside**
Terraform/fabric-cicd and is archived after cutover. It reads `retail-demo-dev`
**strictly read-only**.

**Recommended mechanism — Spark CTAS via ABFSS**, executed inside the target
(silver/gold) workspace, opening the old lakehouse read-only. It is Delta-native
(preserves schema, types, partitioning — satisfying D2), asserts row-count parity
in the same job, needs no live shortcut back to the old workspace, and runs on
the capacity you already manage. (Alternatives — a temporary shortcut then
materialize, or `azcopy` of Delta folders — respectively risk a lingering live
dependency on the old workspace or metadata drift, and are not recommended.)

```python
# --- ONE-OFF COPY (Track 3b). NOT part of IaC. Delete/archive after cutover. ---
# Source is OPENED READ-ONLY: only spark.read is ever called against it.
OLD_WS   = "5219ac70-71d4-4dfc-af32-5b8a6c29a471"   # retail-demo-dev workspace GUID
OLD_LH   = "fc9ed7b6-6723-4116-8bf1-278135865270"   # retail_lakehouse item GUID
OLD_BASE = f"abfss://{OLD_WS}@onelake.dfs.fabric.microsoft.com/{OLD_LH}/Tables"

spark.sql("CREATE SCHEMA IF NOT EXISTS silver")
for t in SILVER_TABLES:
    src = spark.read.format("delta").load(f"{OLD_BASE}/silver/{t}")  # READ ONLY
    src.write.format("delta").mode("overwrite").saveAsTable(f"silver.{t}")
    assert spark.table(f"silver.{t}").count() == src.count(), f"row mismatch: {t}"
```

A parallel notebook in `retail-gold-dev` copies the 9 gold aggregates (and, if
desired, the 4 ML outputs) from `{OLD_BASE}/gold/<table>` into `gold.<table>`.
**No write path to `OLD_BASE` exists anywhere in these notebooks.** After cutover
validation passes, archive or delete the copy notebooks and record the run in the
migration log.

## Shortcut wiring

OneLake shortcuts give a single physical copy per layer while allowing cross-layer
reads. Reuse the pattern in
[`fabric/lakehouse/01-create-bronze-shortcuts.ipynb`](https://github.com/amattas/retail-demo/blob/main/fabric/lakehouse/01-create-bronze-shortcuts.ipynb).

| Consumer | Target | Tables / schema | Direction | Purpose |
| --- | --- | --- | --- | --- |
| `silver_lh` | `bronze_lh` + bronze Eventhouses | raw landing + `cusn` event tables | silver → bronze | silver transforms read raw/streaming events |
| `gold_lh` | `silver_lh` | all **25** `silver.*` dims+facts | gold → silver | **required** so the single Direct Lake expression resolves the 25 `schemaName: silver` partitions from within `gold_lh` |
| `ds_lh` | `silver_lh` | `silver.*` (non-PII per OneLake role) | ds → silver | ML feature reads |
| `ds_lh` | `gold_lh` | `gold.*` aggregates | ds → gold | ML reads curated aggregates |

- Each layer **physically owns** its curated tables (D2); shortcuts are read-only
  projections for cross-layer consumption only.
- The transform/model identity in the consumer workspace must hold **read** on the
  upstream lakehouse — grant via the layer's Entra group + OneLake data-access
  role.
- Gold's `silver.*` shortcuts must preserve the `silver` schema name so the TMDL
  `schemaName: silver` partitions resolve unchanged (no per-table TMDL edits).

## Semantic-model rebind

**Single point of change.** The model binds all 38 tables through one M
expression in
[`expressions.tmdl`](https://github.com/amattas/retail-demo/blob/main/fabric/powerbi/retail_model.SemanticModel/definition/expressions.tmdl):

```
expression 'DirectLake - retail_lakehouse' =
    let
        Source = AzureStorage.DataLake("https://onelake.dfs.fabric.microsoft.com/5219ac70-71d4-4dfc-af32-5b8a6c29a471/fc9ed7b6-6723-4116-8bf1-278135865270", [HierarchicalNavigation=true])
    in
        Source
```

- `5219ac70-71d4-4dfc-af32-5b8a6c29a471` = retail-demo-dev workspace GUID
- `fc9ed7b6-6723-4116-8bf1-278135865270` = retail_lakehouse item GUID

**Edit:** replace both GUIDs with the **new `retail-gold-dev` workspace GUID** and
the **new `gold_lh` lakehouse item GUID** (from the governance Terraform outputs).
`gold_lh` is the bind anchor because the model reads both `gold.*` (owned) and
`silver.*` (shortcut into `gold_lh`); a Direct Lake expression points at exactly
one lakehouse.

**Do not edit (verify only):** the per-table partitions keep
`expressionSource: 'DirectLake - retail_lakehouse'` and their
`schemaName`/`entityName`; `model.tmdl`'s `PBI_QueryOrder` keeps the expression
**name** (only the Source URL changes). A cosmetic rename to `'DirectLake -
gold_lh'` would touch all 38 `expressionSource` lines and is **not recommended**.

Ship the edited `expressions.tmdl` via fabric-cicd into `retail-gold-dev`, point
the gold env's bound-lakehouse config at `gold_lh`, and trigger a refresh/reframe
after rebind.

## Data-agent re-grounding

[`fabric/data-agents/retail-semantic-model-agent.DataAgent`](https://github.com/amattas/retail-demo/blob/main/fabric/data-agents/)
grounds on the semantic model, so once the model is rebound its *content*
grounding is intact — but its **datasource pointers carry the old workspace/model
GUIDs**. Update `artifactId` (old model GUID
`07e6f51e-aaac-4594-bf50-94db9c1daf89`) and `workspaceId` (old
`5219ac70-…`) to the new gold values in **both**
`Files/Config/draft/…/datasource.json` and `Files/Config/published/…/datasource.json`,
then redeploy and re-publish the agent. The nested `elements[]` are keyed by the
model's lineage tags (preserved across the rebind) — verify a sample after
publish. Re-apply item-level sharing to the `sg-fabric-retail-ai-apps` principals
(Phase 4), since the agent now lives in a new workspace.

## Validation gates

Run **all** gates before declaring cutover-ready; `retail-demo-dev` stays live for
side-by-side comparison. For Track 3b compare new vs old (read-only); for Track 3a
compare new vs the *expected* generated counts for the same seed/date range.

1. **Row-count parity** — per-table `count()` new vs old/expected; assert zero
   mismatches across the 25 silver + 13 gold tables.
2. **Column/schema parity** — assert the target schema still contains every
   `sourceColumn` the TMDL binds (several facts keep TMDL-bound PascalCase
   columns, e.g. `fact_promo_lines.ReceiptId`). The repo's
   `tests/generation/test_schema_contract.py` remains the arbiter that every TMDL
   `sourceColumn` exists in `schemas.py`.
3. **Semantic-model / report refresh** — reframe the rebound `retail_model` (no
   partition errors ⇒ shortcuts resolved); confirm visuals render and headline
   measures (`Total Store Sales`, `Total Store Receipts`, `Avg Store Basket`)
   return non-null and match the old report side-by-side.
4. **Data-agent spot-checks** — ask a fixed question set (e.g. latest-day store
   sales → `sales_minute_store`; top-5 products 15m → `top_products_15m`; daily
   tender mix → `tender_mix_daily`) and diff answers against the old agent.
5. **KQL sanity** — confirm the bronze Eventhouses ingest event tables
   (`receipt_created | where event_ts > ago(1h) | count`) and that silver→bronze
   shortcuts resolve.

**Gate exit criterion:** all five green on dev before any test/prod rollout (D1).

## Cutover and rollback

- **Cutover is additive, not destructive.** The new gold workspace's semantic
  model + data agent + Power BI App (Phase 4, D4) become the published surface for
  report-users. No step modifies or decommissions `retail-demo-dev`.
- **Parallel run.** Keep `retail-demo-dev` live and untouched for an agreed soak
  period; its report/agent remain the fallback.
- **Rollback.** If any gate fails post-cutover, repoint consumers back to the
  `retail-demo-dev` semantic model / report (it never changed). Rollback requires
  **zero** changes to `retail-demo-dev`.
- **Retirement is a separate human decision** made only after sustained parallel
  validation. No automated step deletes the old workspace; the IaC must continue
  to deploy successfully with `retail-demo-dev` absent.
- **Track 3b hygiene.** Archive/delete the one-off copy notebooks; grep the
  deployed TMDL/JSON to prove no binding still references `5219ac70-…` /
  `fc9ed7b6-…`.

## Open items and assumptions

- **New GUIDs** for the four workspaces and lakehouses come from the governance
  Terraform outputs and are substituted into `expressions.tmdl` and
  `datasource.json`.
- **Multi-workspace deploy config.** The repo carries a single `workspace.name` /
  `lakehouse.name` per env today. This runbook assumes per-layer env overlays
  (`dev-bronze/silver/gold/ds`) or an equivalent `workspaces:` map extension; the
  CLI already supports overlay precedence, but the deploy framework must be made
  multi-workspace-aware (the deferred part of the Phase 6 deployment work).
- **Schema names** are assumed `silver` / `gold` (post the `ag/au` rename),
  matching the TMDL `schemaName:` values.
- **Eventhouse placement.** Both Eventhouses and the stream-events writer remain in
  `retail-bronze-dev`; silver reads them via shortcuts.
- **Direct Lake single-lakehouse** constraint drives the `gold_lh` bind anchor and
  the gold→silver shortcuts; if multi-lakehouse binds become available, silver
  could be read directly from `silver_lh` and the shortcut dropped.
