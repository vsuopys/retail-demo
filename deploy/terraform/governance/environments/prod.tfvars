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
  platform-admins = ["00000000-0000-0000-0000-000000000000"]
  data-eng        = ["00000000-0000-0000-0000-000000000000"]
  data-sci        = ["00000000-0000-0000-0000-000000000000"]
  analysts        = ["00000000-0000-0000-0000-000000000000"]
  report-users    = ["00000000-0000-0000-0000-000000000000"]
}

group_sp_members = {
  ai-apps   = ["00000000-0000-0000-0000-000000000000"]
  deploy-sp = ["00000000-0000-0000-0000-000000000000"]
}
