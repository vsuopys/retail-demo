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
