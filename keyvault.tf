resource "random_id" "kv_suffix" {
  for_each = local.kv_instances
  byte_length = 4
  keepers = {
    name_prefix = local.kv_prefix
    instance    = each.key
  }
}

# Used to generate a plausible-looking fake secret value per KV instance.
# 64 bytes -> base64 is 88 chars ending "==", the exact shape of a real
# Azure storage account key.
resource "random_id" "kv_secret_token" {
  for_each    = local.kv_instances
  byte_length = 64
  keepers = {
    instance = each.key
  }
}

resource "azurerm_key_vault" "decoy" {
  for_each            = local.kv_instances
  name                = "${local.kv_prefix}-${random_id.kv_suffix[each.key].hex}"
  resource_group_name = var.resource_group_name
  location            = each.value.location
  tenant_id           = var.tenant_id
  sku_name            = "standard"

  # RBAC-mode — all access control via Azure RBAC, not legacy access policies.
  rbac_authorization_enabled    = true
  public_network_access_enabled = true

  # Soft-delete is mandatory in azurerm >= 4.0. Purge protection off so
  # terraform destroy works without a 90-day soft-delete window.
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  tags = local.common_tags
}

# Grant the Terraform apply principal Secrets Officer on each vault so it can
# write the decoy secret during apply. This is a role assignment for the apply
# principal only — decoy SPs and MIs remain at zero role assignments per the
# inertness guarantee.
resource "azurerm_role_assignment" "kv_apply_principal" {
  for_each             = local.kv_instances
  scope                = azurerm_key_vault.decoy[each.key].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Azure RBAC assignments propagate asynchronously. 60 s covers the typical
# 30–60 s window; rare slow propagation may still cause a 403 on first apply
# (re-running apply resolves it without any state changes needed).
resource "time_sleep" "kv_rbac_propagation" {
  depends_on      = [azurerm_role_assignment.kv_apply_principal]
  create_duration = "60s"
}

resource "azurerm_key_vault_secret" "decoy" {
  for_each     = local.kv_instances
  name         = local.kv_secret_name
  key_vault_id = azurerm_key_vault.decoy[each.key].id

  # If the caller supplies a fake_value, use it; otherwise generate a
  # connection-string-shaped placeholder that looks like a real Azure secret.
  # AccountName: prefix + 8 hex chars, same format as the real decoy accounts
  # and within Azure's 24-char account-name limit — a longer name would be an
  # instant giveaway to anyone who knows Azure.
  value = var.key_vault_secret.fake_value != "" ? var.key_vault_secret.fake_value : (
    "DefaultEndpointsProtocol=https;AccountName=${local.sa_prefix}${substr(random_id.kv_secret_token[each.key].hex, 0, 8)};AccountKey=${random_id.kv_secret_token[each.key].b64_std};EndpointSuffix=core.windows.net"
  )

  tags = local.common_tags

  depends_on = [time_sleep.kv_rbac_propagation]
}

# Deletion guardrail — see the storage lock comment for rationale and limits.
resource "azurerm_management_lock" "keyvault" {
  for_each   = var.deletion_locks_enabled ? local.kv_instances : {}
  name       = "retention-lock"
  scope      = azurerm_key_vault.decoy[each.key].id
  lock_level = "CanNotDelete"
  notes      = "Do not delete - required by data retention policy."
}

# Data-plane audit logging: SecretGet never hits the Activity Log, so without
# this a read of the bait secret produces no detection signal.
resource "azurerm_monitor_diagnostic_setting" "keyvault" {
  for_each                   = var.log_analytics_workspace_id != "" ? local.kv_instances : {}
  name                       = "operational-audit"
  target_resource_id         = azurerm_key_vault.decoy[each.key].id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "AuditEvent"
  }
}
