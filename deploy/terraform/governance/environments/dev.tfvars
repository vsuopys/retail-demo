environment   = "dev"
tenant_id     = "bf3237ff-ecce-4a82-8130-bef8d9453c84" # ContosoVVS2
capacity_name = "fabricdemovvs"

skip_capacity_state_validation = false

# Fabric domain. Domains are tenant-level: the dev apply creates "Retail" and
# assigns the four dev workspaces. See README for the test/prod strategy.
domain_name   = "Retail"
assign_domain = true

# Entra group membership. Replace the placeholder object IDs with real GUIDs.
# These are tenant facts, not committed code - keep real values out of version
# control (e.g. supply via a local override or the CI secret store).
group_user_members = {
  platform-admins = ["00000000-0000-0000-0000-000000000000"]
  data-eng        = ["00000000-0000-0000-0000-000000000000"]
  data-sci        = ["00000000-0000-0000-0000-000000000000"]
  analysts        = ["00000000-0000-0000-0000-000000000000"]
  report-users    = ["00000000-0000-0000-0000-000000000000"]
}

group_sp_members = {
  ai-apps   = ["00000000-0000-0000-0000-000000000000"] # AI application SP object ID(s)
  deploy-sp = ["00000000-0000-0000-0000-000000000000"] # CI/CD deploy SP object ID(s)
}
