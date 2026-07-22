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
