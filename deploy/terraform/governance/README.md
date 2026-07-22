# Governance Terraform root (Phase 1-2)

Identity foundation (Entra security groups) and the medallion **workspace
topology** (bronze / silver / gold / ds-sandbox) for the retail-demo governance
re-architecture, as an independent Terraform root.

This root is **additive**: the existing single-workspace root in
`deploy/terraform/` is unchanged. This one stands up the net-new governed
topology and **never references `retail-demo-dev`** - a clean `terraform apply`
succeeds with the old workspace absent.

## What it creates

| Resource | Detail |
|----------|--------|
| 7 Entra security groups | `sg-fabric-retail-{platform-admins,data-eng,data-sci,analysts,ai-apps,report-users,deploy-sp}` |
| Group memberships | Users (`group_user_members`) + service principals (`group_sp_members`), from `<env>.tfvars` |
| 4 Fabric workspaces | `retail-{bronze,silver,gold,ds-sandbox}-<env>`, all on shared capacity `fabricdemovvs` (D3) |
| 4 Lakehouses | One per layer (`bronze_lh`, `silver_lh`, `gold_lh`, `ds_lh`) - **empty**; each layer physically owns its tables (D2) |
| Fabric domain | `Retail`, with the four workspaces assigned (preview resources) |
| Workspace role assignments | Least-privilege RBAC matrix (below), groups only - never users |
| Azure SQL mirroring (optional) | Connection + Mirrored Database in bronze (16 business tables by default), when `sql_mirroring_enabled` - see below |

### RBAC matrix

| Group           | bronze | silver | gold        | ds-sandbox |
|-----------------|--------|--------|-------------|------------|
| platform-admins | Admin  | Admin  | Admin       | Admin      |
| data-eng        | Member | Member | Contributor | Viewer     |
| data-sci        | -      | Viewer | Viewer      | Member     |
| analysts        | -      | Viewer | Contributor | -          |
| deploy-sp       | Admin  | Admin  | Admin       | Admin      |
| ai-apps         | - (item-level sharing / OneLake grants, Phase 4) |||
| report-users    | - (Power BI App audience, D4 / Phase 4)          |||

`ai-apps` and `report-users` deliberately receive **no** workspace role - they
are absent from the `rbac_matrix` local, so `for_each` emits no grant. Their
access is wired in Phase 4 (item sharing / OneLake, and Power BI App audiences).

## Scope boundary (what this root does NOT do)

- No data-copy logic. Lakehouses are created empty; data lands in Phase 3
  (`retail-setup` generation, or a one-off read-only copy runbook - outside IaC).
- No workload items (notebooks, semantic model, data agents, eventhouses). Those
  deploy per-workspace via `fabric-cicd` in Phase 3/6. (Exception: the optional
  Azure SQL Mirrored Database below, which is opt-in and off by default.)
- No reference to `retail-demo-dev` (immutability constraint).

## Prerequisites

- **Providers:** `microsoft/fabric >= 1.0.0` (pinned 1.12.0 in the sibling root)
  and `hashicorp/azuread >= 2.50, < 4.0`.
- **Auth (outside Terraform):** `az login` into tenant `ContosoVVS2`, matching
  `deploy/config/deploy.yml` (`auth.mode: azure_cli`). For CI, the deploy SP
  authenticates via `ARM_*` / `FABRIC_*` env vars.
- **Operator rights:** Fabric administrator (domain create + capacity assign) and
  Entra Groups Administrator / group ownership (group create + membership).
- **Deploy-SP bootstrap:** if the same `deploy-sp` runs this Terraform, it must
  already exist with group-write + Fabric-admin rights *before* the first apply -
  you cannot bootstrap the identity running the apply. Provision
  `sg-fabric-retail-deploy-sp` and its membership out-of-band the first time.

## Usage (dev first - D1)

```powershell
cd deploy\terraform\governance
terraform init
terraform validate
terraform plan  -var-file="environments\dev.tfvars"
terraform apply -var-file="environments\dev.tfvars"
```

Fill the placeholder object IDs in `environments\dev.tfvars` with real user / SP
GUIDs first. Entra object IDs are directory GUIDs, not secrets, so they are
committed for this demo tenant; if you prefer to keep them out of version
control, move them to a local override file or the CI secret store. Stand up
`test` / `prod` later with their own tfvars - no code changes needed.

## Domain strategy across environments

A Fabric **domain is tenant-level**, not per-environment. `dev.tfvars` sets
`assign_domain = true` (creates `Retail`, assigns the four dev workspaces).
`test.tfvars` / `prod.tfvars` default to `assign_domain = false` to avoid a
duplicate-domain conflict on the shared `Retail` domain; assign their workspaces
to `Retail` out-of-band, **or** switch to a dedicated child domain per
environment (`domain_name = "Retail-Test"` + `assign_domain = true`). Choose one
strategy before standing up test/prod.

## Optional: domain-admin delegation

Set `delegate_domain_admin = true` to grant the `platform-admins` group the
`Admins` role on the `Retail` domain (`fabric_domain_role_assignments`). Off by
default.

## Optional: Azure SQL mirroring into bronze

Set `sql_mirroring_enabled = true` to replicate the retail OLTP database (Azure
SQL) into `retail-bronze-<env>` as a Fabric **Mirrored Database**. By default the
**16 business tables** are mirrored (`mirror_tables`), deliberately **excluding**
the `retail._fk_backup` bulk-load helper. Set `mirror_tables = []` to mirror the
**whole database** instead (all tables, auto-adding new ones). Data lands in
OneLake as Delta under the source schema (`mirror_source_schema`, default
`retail`).

Resources created when enabled (`mirroring.tf`):

| Resource | Detail |
|----------|--------|
| `fabric_connection.sql_mirror` | Cloud connection (`type = SQL`) to `mirror_sql_server` / `mirror_sql_database`, Service Principal auth |
| `fabric_mirrored_database.sql_mirror` | Mirrored Database item in the bronze workspace, `mirror_tables` (default 16 business tables; excludes `retail._fk_backup`), Delta |
| `fabric_workspace_role_assignment.sql_server_identity` | Optional - grants the SQL server managed identity `Contributor` on bronze (only when `mirror_sql_server_identity_object_id` is set) |

**Source-side prerequisites** (not managed by Terraform - Fabric mirroring
requirements):

1. **Enable the system-assigned managed identity** on the Azure SQL logical
   server (`retail-erp-demo-sql`).
2. **Create the connection SP as a SQL user** on the source database - run
   [`mirroring/grant-sp-sql-user.sql`](mirroring/grant-sp-sql-user.sql) once,
   connected as an Entra admin. The connection test authenticates as this SP.
3. **Let Fabric write the mirror**: grant the SQL server managed identity
   Read+Write on the mirrored database. Set `mirror_sql_server_identity_object_id`
   to automate the workspace-role grant, or grant it in the Fabric portal.

**Credentials.** The SP **client secret is write-only** and must be supplied
outside Terraform - it is never stored in state or committed:

```powershell
$env:TF_VAR_mirror_sp_client_secret = "<sp client secret>"
terraform apply -var-file="environments\dev.tfvars" -var="sql_mirroring_enabled=true"
```

Non-secret source facts (`mirror_sql_server`, `mirror_sql_database`,
`mirror_source_schema`), the SP `mirror_sp_client_id`, and
`mirror_sql_server_identity_object_id` are set in `dev.tfvars` (client IDs and
directory object IDs are not secrets). Only the SP secret stays out of source
control. Rotate it by incrementing `mirror_sp_client_secret_version` (write-only
values are not diffable). After apply, wire bronze->silver shortcuts to
`mirrored_database_onelake_tables_path`.

**Start mirroring (manual step).** Terraform creates the Mirrored Database in the
`Initialized` state but does **not** start replication - the provider has no
start argument, so starting is a deliberate manual/API action after apply (and
after the source-side prerequisites are in place). Start it in the Fabric portal
(open the mirrored database -> **Monitor/Configure** -> start), or via REST:

```powershell
$ws  = "<bronze workspace id>"          # terraform output workspace_ids["bronze"]
$md  = "<mirrored database id>"          # terraform output mirrored_database_id
$tok = az account get-access-token --resource "https://api.fabric.microsoft.com" --query accessToken -o tsv
$h   = @{ Authorization = "Bearer $tok" }
Invoke-RestMethod -Headers $h -Method Post `
  -Uri "https://api.fabric.microsoft.com/v1/workspaces/$ws/mirroredDatabases/$md/startMirroring"
# Check progress:
Invoke-RestMethod -Headers $h -Method Post `
  -Uri "https://api.fabric.microsoft.com/v1/workspaces/$ws/mirroredDatabases/$md/getMirroringStatus"
```

Changing `mirror_tables` on an already-running mirror requires stop ->
re-apply/updateDefinition -> start (the table-list change re-seeds the snapshot).

## Outputs

`workspace_ids`, `workspace_names`, `lakehouse_ids`, `lakehouse_names`,
`group_object_ids`, `domain_id` - keyed by layer / group. These feed downstream
`fabric-cicd` per-workspace `parameter.yml` find/replace and Phase 4/5 wiring.
When mirroring is enabled, `mirrored_database_id`,
`mirrored_database_onelake_tables_path`, and `mirror_connection_id` are also
emitted (else `null`).
