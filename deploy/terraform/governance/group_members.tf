# Membership is data-driven so object IDs live in <env>.tfvars (tenant facts, not
# code). Human members and SP members are separate maps because they are supplied
# in separate variables; the resource wiring is otherwise identical.

locals {
  user_memberships = merge([
    for gkey, ids in var.group_user_members : {
      for oid in ids : "${gkey}:${oid}" => { group = gkey, oid = oid }
    }
  ]...)

  sp_memberships = merge([
    for gkey, ids in var.group_sp_members : {
      for oid in ids : "${gkey}:${oid}" => { group = gkey, oid = oid }
    }
  ]...)
}

resource "azuread_group_member" "users" {
  for_each = local.user_memberships

  group_object_id  = azuread_group.retail[each.value.group].object_id
  member_object_id = each.value.oid
}

resource "azuread_group_member" "service_principals" {
  for_each = local.sp_memberships

  group_object_id  = azuread_group.retail[each.value.group].object_id
  member_object_id = each.value.oid
}
