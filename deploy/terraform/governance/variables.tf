variable "environment" {
  type        = string
  description = "Deployment environment name: dev, test, or prod. Drives workspace names (retail-<layer>-<environment>)."

  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "environment must be one of: dev, test, prod."
  }
}

variable "tenant_id" {
  type        = string
  default     = null
  nullable    = true
  description = "Microsoft Entra tenant ID (ContosoVVS2). Authentication is supplied outside Terraform."
}

variable "subscription_id" {
  type        = string
  default     = null
  nullable    = true
  description = "Azure subscription ID for CI environments that need it."
}

variable "capacity_name" {
  type        = string
  default     = "fabricdemovvs"
  description = "Shared Fabric capacity display name assigned to all four medallion workspaces (D3: single shared capacity, chargeback by workspace)."
}

variable "skip_capacity_state_validation" {
  type        = bool
  default     = false
  description = "Skip capacity state validation when the caller cannot list capacities."
}

variable "domain_name" {
  type        = string
  default     = "Retail"
  description = "Fabric domain that groups the four medallion workspaces. Domains are tenant-level; see README for the test/prod strategy."

  validation {
    condition     = length(var.domain_name) <= 40
    error_message = "domain_name must be at most 40 characters (Fabric domain display-name limit)."
  }
}

variable "domain_description" {
  type        = string
  default     = "Retail medallion domain (bronze/silver/gold/ds-sandbox)."
  description = "Description for the Fabric domain."
}

variable "assign_domain" {
  type        = bool
  default     = true
  description = "Create the Fabric domain and assign the four workspaces to it. Set false in an environment that reuses a domain created by another environment's apply (domains are tenant-level)."
}

variable "delegate_domain_admin" {
  type        = bool
  default     = false
  description = "Delegate Fabric domain administration to the platform-admins group. Requires the fabric_domain_role_assignments resource; verify attribute names against your provider version before enabling."
}

variable "group_user_members" {
  type        = map(list(string))
  default     = {}
  description = "Entra user object IDs per group key (platform-admins, data-eng, data-sci, analysts, report-users). Object IDs are environment facts supplied in <env>.tfvars, never committed as code."
}

variable "group_sp_members" {
  type        = map(list(string))
  default     = {}
  description = "Service-principal (enterprise application) object IDs per group key (ai-apps, deploy-sp). Use the SP object ID, not the app registration client ID."
}

# --- Azure SQL -> Fabric Mirroring (bronze) -----------------------------------

variable "sql_mirroring_enabled" {
  type        = bool
  default     = false
  description = "Opt-in: create the Azure SQL source connection and Mirrored Database in the bronze workspace. Requires the mirror_* variables and the source-side prerequisites (see governance/README.md)."
}

variable "mirror_display_name" {
  type        = string
  default     = "retail_oltp_mirrored"
  description = "Display name of the Mirrored Database item created in the bronze workspace."
}

variable "mirror_connection_display_name" {
  type        = string
  default     = "retail-oltp-sql"
  description = "Display name of the Fabric cloud connection to the source Azure SQL database."
}

variable "mirror_sql_server" {
  type        = string
  default     = null
  nullable    = true
  description = "Fully qualified Azure SQL server name for the mirror source, e.g. retail-erp-demo-sql.database.windows.net. Required when sql_mirroring_enabled is true."
}

variable "mirror_sql_database" {
  type        = string
  default     = null
  nullable    = true
  description = "Source Azure SQL database name to mirror (all tables), e.g. hallmarkerp. Required when sql_mirroring_enabled is true."
}

variable "mirror_source_schema" {
  type        = string
  default     = "retail"
  description = "Source schema to preserve as the mirrored database default schema (target defaultSchema). The retail OLTP tables live in the `retail` schema."
}

variable "mirror_tables" {
  type = list(string)
  default = [
    "customers",
    "distribution_centers",
    "geographies",
    "inventory_transactions",
    "online_order_lines",
    "online_orders",
    "payments",
    "products",
    "reorders",
    "sale_lines",
    "sales",
    "shipment_lines",
    "shipment_movements",
    "stockouts",
    "stores",
    "trucks",
  ]
  description = "Explicit list of source tables (in mirror_source_schema) to mirror. Defaults to the 16 business tables, deliberately excluding the retail._fk_backup bulk-load helper. Set to [] to mirror the WHOLE database instead (all tables, auto-adding new ones)."
}

variable "mirror_sp_client_id" {
  type        = string
  default     = null
  nullable    = true
  description = "Application (client) ID of the service principal the connection uses to authenticate to the source Azure SQL database. The SP must be a SQL user on the source DB (see mirroring/grant-sp-sql-user.sql). Required when sql_mirroring_enabled is true."
}

variable "mirror_sp_tenant_id" {
  type        = string
  default     = null
  nullable    = true
  description = "Entra tenant ID for the mirror connection service principal. Defaults to var.tenant_id when null."
}

variable "mirror_sp_client_secret" {
  type        = string
  default     = null
  nullable    = true
  sensitive   = true
  description = "Client secret of the mirror connection service principal. Supply via TF_VAR_mirror_sp_client_secret; never commit it to tfvars. This is a write-only value and is not persisted in state."
}

variable "mirror_sp_client_secret_version" {
  type        = number
  default     = 1
  description = "Version counter for mirror_sp_client_secret. Increment to force the connection to re-apply a rotated secret (write-only values are not diffable)."
}

variable "mirror_skip_test_connection" {
  type        = bool
  default     = false
  description = "Skip the connection test on create/update. Leave false so a misconfigured SP or missing SQL grant fails fast; set true only if the runner cannot reach the SQL server at apply time."
}

variable "mirror_sql_server_identity_object_id" {
  type        = string
  default     = null
  nullable    = true
  description = "Object ID of the source Azure SQL server's system-assigned managed identity. When set, the bronze workspace grants it Contributor so Fabric can write mirrored data. Leave null to grant this in the Fabric portal instead."
}
