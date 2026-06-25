# =============================================================================
# Input-variable contract — terraform-azure-deception
# Design locked 2026-06-04 (Epic D.1). Mirror the AWS/GCP shape where possible.
# =============================================================================

# Placement

variable "subscription_id" {
  description = "Azure subscription the decoys land in (client's choice)."
  type        = string
}

variable "tenant_id" {
  description = "Azure AD tenant ID where the Service Principal is created."
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group for subscription-scoped decoys. The module does NOT create the RG."
  type        = string

  validation {
    condition     = length(var.resource_group_name) <= 90
    error_message = "Azure resource group name max length is 90 chars."
  }

  validation {
    condition     = can(regex("^[a-zA-Z0-9_()\\.\\-]+$", var.resource_group_name))
    error_message = "Resource group name may only contain alphanumeric characters and _ ( ) . - ."
  }

  validation {
    condition     = !can(regex("(?i)(cyngular|deception|decoy|honeytoken|bait|trap|observer)", var.resource_group_name))
    error_message = "resource_group_name must not contain forbidden tokens (cyngular, deception, decoy, honeytoken, bait, trap, observer)."
  }
}

# Regional fan-out

variable "locations" {
  description = "Azure regions for regional decoy kinds (Storage Account, Key Vault). SP and Managed Identity are tenant/subscription scoped."
  type        = list(string)
  default     = ["eastus"]

  validation {
    condition     = length(var.locations) > 0
    error_message = "At least one location is required."
  }
}

# Attribution tag

variable "tracking_tag_key" {
  description = "Tag key applied to every decoy. Should mimic a normal client tag."
  type        = string

  validation {
    condition     = length(var.tracking_tag_key) <= 512
    error_message = "Azure tag key max length is 512 chars."
  }

  validation {
    condition     = !can(regex("(?i)(cyngular|deception|decoy|honeytoken|bait|trap|observer)", var.tracking_tag_key))
    error_message = "tracking_tag_key must not contain forbidden tokens."
  }
}

variable "tracking_tag_value" {
  description = "Tag value applied to every decoy."
  type        = string

  validation {
    condition     = length(var.tracking_tag_value) <= 256
    error_message = "Azure tag value max length is 256 chars."
  }

  validation {
    condition     = !can(regex("(?i)(cyngular|deception|decoy|honeytoken|bait|trap|observer)", var.tracking_tag_value))
    error_message = "tracking_tag_value must not contain forbidden tokens."
  }
}

# Per-kind blocks

variable "service_principal" {
  description = "Service Principal honeytokens. Zero role assignments; optional Conditional Access blocking sign-ins."
  type = object({
    enabled                  = optional(bool, false)
    count                    = optional(number, 0)
    name_prefix              = optional(string, "")
    generate_secret          = optional(bool, false)
    secret_expiry_years      = optional(number, 5)
    conditional_access_block = optional(bool, false)
  })
  default = {}

  validation {
    condition     = !can(regex("(?i)(cyngular|deception|decoy|honeytoken|bait|trap|observer)", var.service_principal.name_prefix))
    error_message = "service_principal.name_prefix must not contain forbidden tokens."
  }

  validation {
    condition     = length(var.service_principal.name_prefix) <= 240
    error_message = "service_principal.name_prefix must be <= 240 chars (leaves room for index suffix within 256-char display_name limit)."
  }

  validation {
    condition     = var.service_principal.count >= 0
    error_message = "service_principal.count must be >= 0."
  }

  validation {
    condition     = var.service_principal.secret_expiry_years > 0
    error_message = "service_principal.secret_expiry_years must be > 0."
  }
}

variable "managed_identity" {
  description = "User-Assigned Managed Identity honeytokens. Never associated with compute."
  type = object({
    enabled     = optional(bool, false)
    count       = optional(number, 0)
    name_prefix = optional(string, "")
  })
  default = {}

  validation {
    condition     = !can(regex("(?i)(cyngular|deception|decoy|honeytoken|bait|trap|observer)", var.managed_identity.name_prefix))
    error_message = "managed_identity.name_prefix must not contain forbidden tokens."
  }

  validation {
    condition     = length(var.managed_identity.name_prefix) <= 120
    error_message = "managed_identity.name_prefix must be <= 120 chars (Azure MI name max is 128)."
  }

  validation {
    condition     = var.managed_identity.count >= 0
    error_message = "managed_identity.count must be >= 0."
  }
}

variable "storage_account" {
  description = "Storage Account decoys. Public network access enabled, no anonymous read, RBAC-only data plane. Fans out over var.locations."
  type = object({
    enabled     = optional(bool, false)
    count       = optional(number, 0)
    name_prefix = optional(string, "")
    decoy_blobs = optional(list(object({
      name    = string
      content = string
    })), [])
  })
  default = {}

  validation {
    condition     = !can(regex("(?i)(cyngular|deception|decoy|honeytoken|bait|trap|observer)", var.storage_account.name_prefix))
    error_message = "storage_account.name_prefix must not contain forbidden tokens."
  }

  validation {
    condition     = length(var.storage_account.name_prefix) <= 11
    error_message = "storage_account.name_prefix must be <= 11 chars (module appends an 8-char random suffix; total must stay within Azure's 24-char limit)."
  }

  validation {
    condition     = var.storage_account.name_prefix == "" || can(regex("^[a-z0-9]+$", var.storage_account.name_prefix))
    error_message = "storage_account.name_prefix must be lowercase alphanumeric only (Azure storage account name constraint)."
  }

  validation {
    condition     = var.storage_account.count >= 0
    error_message = "storage_account.count must be >= 0."
  }

  validation {
    condition = alltrue([
      for b in var.storage_account.decoy_blobs :
      !can(regex("(?i)(cyngular|deception|decoy|honeytoken|bait|trap|observer)", b.name))
    ])
    error_message = "storage_account.decoy_blobs[*].name must not contain forbidden tokens."
  }
}

variable "key_vault_secret" {
  description = "Key Vault Secret decoys (one KV per instance × location, holds a fake secret). RBAC-mode KV. Fans out over var.locations."
  type = object({
    enabled     = optional(bool, false)
    count       = optional(number, 0)
    name_prefix = optional(string, "")
    fake_value  = optional(string, "")
  })
  default = {}

  validation {
    condition     = !can(regex("(?i)(cyngular|deception|decoy|honeytoken|bait|trap|observer)", var.key_vault_secret.name_prefix))
    error_message = "key_vault_secret.name_prefix must not contain forbidden tokens."
  }

  validation {
    condition     = length(var.key_vault_secret.name_prefix) <= 14
    error_message = "key_vault_secret.name_prefix must be <= 14 chars (module appends '-XXXX' suffix; total must stay within Azure's 24-char KV name limit)."
  }

  validation {
    condition     = var.key_vault_secret.name_prefix == "" || can(regex("^[a-zA-Z]", var.key_vault_secret.name_prefix))
    error_message = "key_vault_secret.name_prefix must start with a letter (Azure Key Vault name constraint)."
  }

  validation {
    condition     = var.key_vault_secret.name_prefix == "" || can(regex("^[a-zA-Z0-9\\-]+$", var.key_vault_secret.name_prefix))
    error_message = "key_vault_secret.name_prefix must be alphanumeric + hyphens only (Azure Key Vault name constraint)."
  }

  validation {
    condition     = var.key_vault_secret.count >= 0
    error_message = "key_vault_secret.count must be >= 0."
  }

  validation {
    condition     = !can(regex("(?i)(cyngular|deception|decoy|honeytoken|bait|trap|observer)", var.key_vault_secret.fake_value))
    error_message = "key_vault_secret.fake_value must not contain forbidden tokens."
  }
}

# Lure tags

variable "lure_tags" {
  description = "Believable operational tags applied to every decoy alongside the tracking tag. No Cyngular reference."
  type        = map(string)
  default = {
    environment = "prod"
    owner       = "legacy-team"
  }

  validation {
    condition = alltrue([
      for v in concat(keys(var.lure_tags), values(var.lure_tags)) :
      !can(regex("(?i)(cyngular|deception|decoy|honeytoken|bait|trap|observer)", v))
    ])
    error_message = "lure_tags keys and values must not contain forbidden tokens."
  }

  validation {
    condition = alltrue([
      for k in keys(var.lure_tags) : length(k) <= 512
    ])
    error_message = "All lure_tags key lengths must be <= 512 chars."
  }

  validation {
    condition = alltrue([
      for v in values(var.lure_tags) : length(v) <= 256
    ])
    error_message = "All lure_tags value lengths must be <= 256 chars."
  }
}
