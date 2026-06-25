# =============================================================================
# Attribution outputs — per-kind IDs keyed by instance, plus tracking tag.
# Detection uses these to match Azure activity / sign-in log events back to
# the client that owns this decoy set.
# =============================================================================

output "service_principal_object_ids" {
  description = "Object IDs of the created SP honeytokens, keyed by instance. Primary key for matching directory audit log events."
  value       = { for k, v in azuread_service_principal.decoy : k => v.object_id }
}

output "service_principal_app_ids" {
  description = "App (client) IDs of the created SP honeytokens, keyed by instance. Sign-in logs reference app_id; directory audit logs reference object_id."
  value       = { for k, v in azuread_application.decoy : k => v.client_id }
}

output "service_principal_secrets" {
  description = "Client secrets for SPs created with generate_secret = true, keyed by instance. Empty map when generate_secret = false."
  value       = { for k, v in azuread_application_password.decoy : k => v.value }
  sensitive   = true
}

output "managed_identity_ids" {
  description = "Resource IDs of the created Managed Identity honeytokens, keyed by instance."
  value       = { for k, v in azurerm_user_assigned_identity.decoy : k => v.id }
}

output "managed_identity_principal_ids" {
  description = "Principal IDs of the Managed Identity honeytokens, keyed by instance. Used by detection to match RBAC and sign-in events."
  value       = { for k, v in azurerm_user_assigned_identity.decoy : k => v.principal_id }
}

output "storage_account_ids" {
  description = "Resource IDs of the created Storage Account decoys, keyed by 'instance-location'."
  value       = { for k, v in azurerm_storage_account.decoy : k => v.id }
}

output "key_vault_secret_ids" {
  description = "Versioned resource IDs of the Key Vault Secret decoys, keyed by 'instance-location'."
  value       = { for k, v in azurerm_key_vault_secret.decoy : k => v.id }
}

output "tracking_tag" {
  description = "The tracking tag (key/value) applied to every decoy. Used as the platform-side lookup index for per-client decoy sets."
  value = {
    key   = var.tracking_tag_key
    value = var.tracking_tag_value
  }
}
