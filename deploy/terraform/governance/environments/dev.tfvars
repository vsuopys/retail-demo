environment   = "dev"
tenant_id     = "bf3237ff-ecce-4a82-8130-bef8d9453c84" # ContosoVVS2
capacity_name = "fabricdemovvs"

skip_capacity_state_validation = false

# Fabric domain. Domains are tenant-level: the dev apply creates "Retail" and
# assigns the four dev workspaces. See README for the test/prod strategy.
domain_name   = "Retail"
assign_domain = true

# Entra group membership (ContosoVVS2 / MngEnvMCAP245699 tenant). Object IDs are
# directory GUIDs, not secrets. Users:
#   57d5057f-... = System Administrator (admin@MngEnvMCAP245699.onmicrosoft.com)
#   62283ea1-... = Vytas Suopys (vysuopys_microsoft.com)
group_user_members = {
  platform-admins = ["57d5057f-41c8-4327-8da7-3aebcbb5ae11", "62283ea1-aa5f-428a-a425-6e10555f830b"]
  data-eng        = ["57d5057f-41c8-4327-8da7-3aebcbb5ae11", "62283ea1-aa5f-428a-a425-6e10555f830b"]
  data-sci        = ["57d5057f-41c8-4327-8da7-3aebcbb5ae11", "62283ea1-aa5f-428a-a425-6e10555f830b"]
  analysts        = ["57d5057f-41c8-4327-8da7-3aebcbb5ae11", "62283ea1-aa5f-428a-a425-6e10555f830b"]
  report-users    = ["57d5057f-41c8-4327-8da7-3aebcbb5ae11", "62283ea1-aa5f-428a-a425-6e10555f830b"]
}

# Service-principal (enterprise application) object IDs.
#   2591597e-... = retail-demo-crossauth (AI application SP)
#   f1bdbcf3-... = retail-demo-dev       (CI/CD deploy SP)
group_sp_members = {
  ai-apps   = ["2591597e-95bd-47b2-8559-0228f50035b7"]
  deploy-sp = ["f1bdbcf3-da75-45cc-aed9-a0c06c87d089"]
}

# --- Azure SQL -> Fabric Mirroring (bronze) -----------------------------------
# Opt-in. Flip sql_mirroring_enabled to true after completing the source-side
# prerequisites (see governance/README.md "SQL mirroring"):
#   1. Enable the system-assigned managed identity on retail-erp-demo-sql.
#   2. Create the connection SP as a SQL user on hallmarkerp
#      (mirroring/grant-sp-sql-user.sql).
#   3. Provide the SP secret via TF_VAR_mirror_sp_client_secret (never here).
# Non-secret source facts (server/database/schema) are safe to commit; the SP
# client id is not a secret but the secret must stay out of source control.
sql_mirroring_enabled = false

mirror_sql_server    = "retail-erp-demo-sql.database.windows.net"
mirror_sql_database  = "hallmarkerp"
mirror_source_schema = "retail"

# Dedicated, reusable source-integration SP (retail-source-integrator). Client
# IDs are not secrets, so this is committed; the secret is supplied only via
# TF_VAR_mirror_sp_client_secret at apply time.
mirror_sp_client_id = "f7d9e426-f606-40f3-8630-628e0e79a28b"

# mirror_sp_tenant_id                  = "bf3237ff-ecce-4a82-8130-bef8d9453c84"  # defaults to tenant_id
# Source SQL server (retail-erp-demo-sql, sub fabric-3 / rg-fabricdemos) has its
# system-assigned managed identity enabled; this is its Entra object ID. Fabric
# grants it Contributor on bronze so it can land mirrored data.
mirror_sql_server_identity_object_id = "2f634058-9f16-457e-a672-987f6b1f55ce"
# Secret: setx / $env:TF_VAR_mirror_sp_client_secret before apply.
