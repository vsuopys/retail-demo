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
  deploy per-workspace via `fabric-cicd` in Phase 3/6.
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
GUIDs first. Keep real object IDs out of version control (local override file or
CI secret store). Stand up `test` / `prod` later with their own tfvars - no code
changes needed.

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

## Outputs

`workspace_ids`, `workspace_names`, `lakehouse_ids`, `lakehouse_names`,
`group_object_ids`, `domain_id` - keyed by layer / group. These feed downstream
`fabric-cicd` per-workspace `parameter.yml` find/replace and Phase 4/5 wiring.
