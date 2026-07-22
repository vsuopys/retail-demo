environment   = "test"
tenant_id     = "bf3237ff-ecce-4a82-8130-bef8d9453c84" # ContosoVVS2
capacity_name = "fabricdemovvs"

skip_capacity_state_validation = false

# Domains are tenant-level. If test reuses the single "Retail" domain created by
# the dev apply, set assign_domain = false here to avoid a duplicate-domain
# conflict, and assign the test workspaces to "Retail" out-of-band or via a child
# domain. If you instead use a dedicated child domain per environment, set
# domain_name = "Retail-Test" and assign_domain = true. See README.
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
