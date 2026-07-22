# Create the Fabric domain once and assign all four workspaces. Domains are
# tenant-level, so `assign_domain` lets an environment that reuses a domain created
# by another environment's apply skip creation (see README for test/prod strategy).
# fabric_domain and fabric_domain_workspace_assignments are preview resources
# (preview = true in providers.tf). Caller must be a Fabric administrator.
resource "fabric_domain" "retail" {
  count = var.assign_domain ? 1 : 0

  display_name = var.domain_name
  description  = var.domain_description
}

resource "fabric_domain_workspace_assignments" "retail" {
  count = var.assign_domain ? 1 : 0

  domain_id     = fabric_domain.retail[0].id
  workspace_ids = [for k in keys(local.layers) : fabric_workspace.layer[k].id]
}

# OPTIONAL - delegate domain administration to the platform team. Verify the
# fabric_domain_role_assignments resource/attribute names against your provider
# version before enabling (guarded by delegate_domain_admin, default false).
resource "fabric_domain_role_assignments" "admins" {
  count = var.assign_domain && var.delegate_domain_admin ? 1 : 0

  domain_id = fabric_domain.retail[0].id
  role      = "Admins"
  principals = [{
    id   = azuread_group.retail["platform-admins"].object_id
    type = "Group"
  }]
}
