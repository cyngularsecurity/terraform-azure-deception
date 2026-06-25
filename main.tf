# terraform-azure-deception
# Design locked 2026-06-04 (Epic D.1). Azure counterpart of terraform-aws-deception.
#
# Resource files:
#   locals.tf            — shared locals, instance maps, derived names
#   service_principal.tf — azuread_application, azuread_service_principal, azuread_application_password, azuread_conditional_access_policy
#   managed_identity.tf  — azurerm_user_assigned_identity
#   storage.tf           — azurerm_storage_account, azurerm_storage_container, azurerm_storage_blob
#   keyvault.tf          — azurerm_key_vault, azurerm_key_vault_secret
