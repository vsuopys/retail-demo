output "workspace_ids" {
  value       = { for k, w in fabric_workspace.layer : k => w.id }
  description = "Layer key -> Fabric workspace ID (bronze/silver/gold/ds-sandbox). Feeds downstream fabric-cicd per-workspace parameter.yml."
}

output "workspace_names" {
  value       = { for k, w in fabric_workspace.layer : k => w.display_name }
  description = "Layer key -> Fabric workspace display name."
}

output "lakehouse_ids" {
  value       = { for k, l in fabric_lakehouse.layer : k => l.id }
  description = "Layer key -> owned Fabric Lakehouse item ID."
}

output "lakehouse_names" {
  value       = { for k, l in fabric_lakehouse.layer : k => l.display_name }
  description = "Layer key -> owned Fabric Lakehouse display name."
}

output "group_object_ids" {
  value       = { for k, g in azuread_group.retail : k => g.object_id }
  description = "Group key -> Entra security group object ID."
}

output "domain_id" {
  value       = var.assign_domain ? fabric_domain.retail[0].id : null
  description = "Fabric Retail domain ID (null when assign_domain is false)."
}

output "mirrored_database_id" {
  value       = local.sql_mirroring_enabled ? fabric_mirrored_database.sql_mirror[0].id : null
  description = "Fabric Mirrored Database item ID in the bronze workspace (null when sql_mirroring_enabled is false)."
}

output "mirrored_database_onelake_tables_path" {
  value       = local.sql_mirroring_enabled ? fabric_mirrored_database.sql_mirror[0].properties.onelake_tables_path : null
  description = "OneLake Tables path of the mirrored database - target for bronze->silver shortcuts."
}

output "mirror_connection_id" {
  value       = local.sql_mirroring_enabled ? fabric_connection.sql_mirror[0].id : null
  description = "Fabric cloud connection ID to the source Azure SQL database (null when sql_mirroring_enabled is false)."
}
