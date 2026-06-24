terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 2.0"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}

provider "azuread" {
  tenant_id = var.tenant_id
}

# ---------------------------------------------------------------------------
# Variables — fill these in for your throwaway subscription / tenant
# ---------------------------------------------------------------------------

variable "subscription_id" {
  description = "Azure subscription to deploy decoys into."
  type        = string
}

variable "tenant_id" {
  description = "Azure AD tenant ID."
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group for subscription-scoped decoys."
  type        = string
}

# ---------------------------------------------------------------------------
# Module invocation
# ---------------------------------------------------------------------------

module "deception" {
  source = "../.."
  # When consuming from the registry, replace source with:
  #   source  = "cyngularsecurity/deception/azure"
  #   version = "~> 0.1"

  subscription_id     = var.subscription_id
  tenant_id           = var.tenant_id
  resource_group_name = var.resource_group_name

  locations = ["eastus", "westus2"]

  tracking_tag_key   = "cost-center"
  tracking_tag_value = "cc-9842"

  lure_tags = {
    environment = "prod"
    owner       = "legacy-team"
    managed-by  = "terraform"
  }

  service_principal = {
    enabled             = true
    count               = 2
    name_prefix         = "legacy-svc"
    generate_secret     = true
    secret_expiry_years = 5
    conditional_access_block = false
  }

  managed_identity = {
    enabled     = true
    count       = 2
    name_prefix = "legacy-identity"
  }

  storage_account = {
    enabled     = true
    count       = 1
    name_prefix = "legacysa"
    # decoy_blobs left empty — module uses the built-in default set
  }

  key_vault_secret = {
    enabled     = true
    count       = 1
    name_prefix = "legacy-kv"
    # fake_value left empty — module generates a connection-string-shaped placeholder
  }
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

output "service_principal_app_ids" {
  value = module.deception.service_principal_app_ids
}

output "service_principal_object_ids" {
  value = module.deception.service_principal_object_ids
}

output "service_principal_secrets" {
  value     = module.deception.service_principal_secrets
  sensitive = true
}

output "managed_identity_ids" {
  value = module.deception.managed_identity_ids
}

output "storage_account_ids" {
  value = module.deception.storage_account_ids
}

output "key_vault_secret_ids" {
  value = module.deception.key_vault_secret_ids
}

output "tracking_tag" {
  value = module.deception.tracking_tag
}
