# =============================================================================
# terraform-azure-deception (DEFERRED SCAFFOLDING)
# Azure counterpart of terraform-aws-deception. Design is NOT yet locked —
# this is a placeholder repo created alongside AWS/GCP. Resource design will
# follow the AWS shape once proven. See references/deception-resource-spec.md
# §Azure for the candidate resource × tag × restriction matrix.
# =============================================================================

locals {
  common_tags = merge(
    var.lure_tags,
    { (var.tracking_tag_key) = var.tracking_tag_value },
  )
}

# Candidate kinds (deferred): Service Principal, Managed Identity,
# Storage Account/Blob, Key Vault Secret.
