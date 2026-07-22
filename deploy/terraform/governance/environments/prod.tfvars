environment   = "prod"
tenant_id     = "bf3237ff-ecce-4a82-8130-bef8d9453c84" # ContosoVVS2
capacity_name = "fabricdemovvs"

skip_capacity_state_validation = false

# See test.tfvars / README for the tenant-level domain strategy. Reusing the
# single "Retail" domain -> assign_domain = false; dedicated child domain ->
# domain_name = "Retail-Prod" and assign_domain = true.
domain_name   = "Retail"
assign_domain = false

group_user_members = {
  platform-admins = ["57d5057f-41c8-4327-8da7-3aebcbb5ae11", "62283ea1-aa5f-428a-a425-6e10555f830b"]
  data-eng        = ["57d5057f-41c8-4327-8da7-3aebcbb5ae11", "62283ea1-aa5f-428a-a425-6e10555f830b"]
  data-sci        = ["57d5057f-41c8-4327-8da7-3aebcbb5ae11", "62283ea1-aa5f-428a-a425-6e10555f830b"]
  analysts        = ["57d5057f-41c8-4327-8da7-3aebcbb5ae11", "62283ea1-aa5f-428a-a425-6e10555f830b"]
  report-users    = ["57d5057f-41c8-4327-8da7-3aebcbb5ae11", "62283ea1-aa5f-428a-a425-6e10555f830b"]
}

group_sp_members = {
  ai-apps   = ["2591597e-95bd-47b2-8559-0228f50035b7"]
  deploy-sp = ["f1bdbcf3-da75-45cc-aed9-a0c06c87d089"]
}
