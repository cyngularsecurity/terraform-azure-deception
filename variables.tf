# =============================================================================
# Input-variable contract (STUB — Azure design not yet locked; deferred until
# the AWS shape is proven, see Track D README). Mirror the AWS contract once
# the Azure resource design is locked.
# =============================================================================

variable "location" {
  description = "Azure region(s) for regional decoy kinds. IAM/identity is tenant-global."
  type        = list(string)
  default     = ["eastus"]
}

variable "tracking_tag_key" {
  description = "Attribution tag key applied to every decoy (should mimic a normal client tag)."
  type        = string
}

variable "tracking_tag_value" {
  description = "Attribution tag value applied to every decoy."
  type        = string
}

variable "lure_tags" {
  description = "Believable operational tags on every decoy. No Cyngular reference."
  type        = map(string)
  default = {
    environment = "prod"
    owner       = "legacy-team"
  }
}

# Per-kind { enabled, count, name_prefix } objects to be added when the Azure
# design is locked: service principal, managed identity, storage account/blob,
# key vault secret (see references/deception-resource-spec.md §Azure).
