# Azure SQL -> Fabric Mirroring into the bronze workspace.
#
# Replicates the retail OLTP database (Azure SQL) into `retail-bronze-<env>` as a
# Fabric Mirrored Database. The whole database is mirrored: mirroring.json omits
# `mountedTables`, so Fabric replicates every table and auto-adds new ones
# (see docs/design/architecture at "Mirrored database item definition").
#
# The feature is opt-in via `sql_mirroring_enabled` so environments without the
# OLTP source (or without the source-side prerequisites in place) skip it.
#
# Prerequisites (NOT managed here - see governance/README.md "SQL mirroring"):
#   1. The source Azure SQL logical server has a system-assigned managed
#      identity enabled.
#   2. The connection's service principal is a SQL user on the source database
#      (run mirroring/grant-sp-sql-user.sql once).
#   3. The SQL server managed identity has Read+Write on the mirrored database -
#      set `mirror_sql_server_identity_object_id` to automate the workspace-role
#      grant below, or grant it in the Fabric portal.

locals {
  sql_mirroring_enabled = var.sql_mirroring_enabled

  # Default the SP tenant to the stack tenant unless overridden.
  mirror_sp_tenant_id = coalesce(var.mirror_sp_tenant_id, var.tenant_id)
}

# Cloud connection to the source Azure SQL database. Credentials are Service
# Principal so the deployment is non-interactive and repeatable; the secret is a
# write-only value supplied outside Terraform (TF_VAR_mirror_sp_client_secret),
# never stored in state or committed to tfvars.
resource "fabric_connection" "sql_mirror" {
  count = local.sql_mirroring_enabled ? 1 : 0

  display_name                        = var.mirror_connection_display_name
  connectivity_type                   = "ShareableCloud"
  privacy_level                       = "Organizational"
  allow_usage_in_user_controlled_code = false

  connection_details = {
    type            = "SQL"
    creation_method = "Sql"
    parameters = [
      {
        name  = "server"
        value = var.mirror_sql_server
      },
      {
        name  = "database"
        value = var.mirror_sql_database
      },
    ]
  }

  credential_details = {
    credential_type       = "ServicePrincipal"
    connection_encryption = "Encrypted"
    single_sign_on_type   = "None"
    skip_test_connection  = var.mirror_skip_test_connection

    service_principal_credentials = {
      client_id                = var.mirror_sp_client_id
      tenant_id                = local.mirror_sp_tenant_id
      client_secret_wo         = var.mirror_sp_client_secret
      client_secret_wo_version = var.mirror_sp_client_secret_version
    }
  }

  lifecycle {
    precondition {
      condition = !local.sql_mirroring_enabled || (
        var.mirror_sql_server != null &&
        var.mirror_sql_database != null &&
        var.mirror_sp_client_id != null &&
        var.mirror_sp_client_secret != null
      )
      error_message = "sql_mirroring_enabled requires mirror_sql_server, mirror_sql_database, mirror_sp_client_id, and mirror_sp_client_secret (via TF_VAR_mirror_sp_client_secret)."
    }
  }
}

# The Mirrored Database item lands in the bronze workspace and replicates the
# whole source database into OneLake as Delta, preserving the source schema
# (`defaultSchema`). All tables are mirrored (mountedTables omitted).
resource "fabric_mirrored_database" "sql_mirror" {
  count = local.sql_mirroring_enabled ? 1 : 0

  display_name = var.mirror_display_name
  description  = "Azure SQL mirroring of ${var.mirror_sql_database} (all tables) into bronze."
  workspace_id = fabric_workspace.layer["bronze"].id
  format       = "Default"

  definition = {
    "mirroring.json" = {
      source = "${path.module}/mirroring/mirroring.json.tmpl"
      tokens = {
        ConnectionId  = fabric_connection.sql_mirror[0].id
        Database      = var.mirror_sql_database
        DefaultSchema = var.mirror_source_schema
      }
    }
  }

  # Provisioning the mirror + SQL analytics endpoint can exceed the default
  # create timeout, especially on a shared/throttled capacity.
  timeouts = {
    create = "30m"
  }
}

# Optional: grant the source SQL server's managed identity write access to the
# bronze workspace so Fabric can land mirrored data. Managed identities are
# service principals in Entra, hence type = "ServicePrincipal". Contributor is
# the least workspace role that includes read+write on items.
resource "fabric_workspace_role_assignment" "sql_server_identity" {
  count = local.sql_mirroring_enabled && var.mirror_sql_server_identity_object_id != null ? 1 : 0

  workspace_id = fabric_workspace.layer["bronze"].id

  principal = {
    id   = var.mirror_sql_server_identity_object_id
    type = "ServicePrincipal"
  }
  role = "Contributor"
}
