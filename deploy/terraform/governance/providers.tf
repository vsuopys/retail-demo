terraform {
  required_version = ">= 1.8, < 2.0"

  required_providers {
    fabric = {
      source  = "microsoft/fabric"
      version = ">= 1.0.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 2.50, < 4.0"
    }
  }
}

# Authentication for both providers is supplied OUTSIDE Terraform (Azure CLI
# `az login` into tenant ContosoVVS2, or CI service-principal env vars), matching
# deploy/config/deploy.yml (auth.mode: azure_cli). Never place secrets in HCL or
# tfvars.
provider "azuread" {
  tenant_id = var.tenant_id
}

provider "fabric" {
  # fabric_domain and fabric_domain_workspace_assignments are preview resources,
  # so preview mode must be enabled at the provider level.
  preview = true
}
