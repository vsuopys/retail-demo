locals {
  # RBAC matrix from the locked governance plan: group key -> { layer key -> role }.
  # Omit a layer to grant NO role there - that omission IS the least-privilege
  # "none". ai-apps and report-users are intentionally ABSENT: they receive no
  # workspace role (item-level sharing / OneLake grants for ai-apps in Phase 4;
  # Power BI App audience for report-users per D4).
  rbac_matrix = {
    platform-admins = { bronze = "Admin", silver = "Admin", gold = "Admin", ds-sandbox = "Admin" }
    data-eng        = { bronze = "Member", silver = "Member", gold = "Contributor", ds-sandbox = "Viewer" }
    data-sci        = { silver = "Viewer", gold = "Viewer", ds-sandbox = "Member" }
    analysts        = { silver = "Viewer", gold = "Contributor" }
    deploy-sp       = { bronze = "Admin", silver = "Admin", gold = "Admin", ds-sandbox = "Admin" }
  }

  # Flatten to one entry per (group, layer) pair that has a role.
  role_assignments = merge([
    for gkey, layers in local.rbac_matrix : {
      for lkey, role in layers :
      "${gkey}:${lkey}" => {
        group = gkey
        layer = lkey
        role  = role
      }
    }
  ]...)
}

resource "fabric_workspace_role_assignment" "governance" {
  for_each = local.role_assignments

  workspace_id = fabric_workspace.layer[each.value.layer].id

  principal = {
    id   = azuread_group.retail[each.value.group].object_id
    type = "Group"
  }
  role = each.value.role
}
