# =============================================================================
# terraform-azure-deception — main resource definitions
# Design locked 2026-06-04 (Epic D.1).
# =============================================================================

locals {
  common_tags = merge(
    var.lure_tags,
    { (var.tracking_tag_key) = var.tracking_tag_value },
  )

  # Instance maps — one entry per created resource unit

  sp_instances = var.service_principal.enabled && var.service_principal.count > 0 ? {
    for i in range(var.service_principal.count) : tostring(i) => i
  } : {}

  sp_secret_instances = var.service_principal.generate_secret ? local.sp_instances : {}

  mi_instances = var.managed_identity.enabled && var.managed_identity.count > 0 ? {
    for i in range(var.managed_identity.count) : tostring(i) => i
  } : {}

  # Storage and KV fan out over instance index × location
  _sa_pairs = var.storage_account.enabled && var.storage_account.count > 0 ? flatten([
    for i in range(var.storage_account.count) : [
      for loc in var.locations : {
        key      = "${i}-${replace(loc, " ", "")}"
        idx      = i
        location = loc
      }
    ]
  ]) : []

  sa_instances = { for p in local._sa_pairs : p.key => p }

  _kv_pairs = var.key_vault_secret.enabled && var.key_vault_secret.count > 0 ? flatten([
    for i in range(var.key_vault_secret.count) : [
      for loc in var.locations : {
        key      = "${i}-${replace(loc, " ", "")}"
        idx      = i
        location = loc
      }
    ]
  ]) : []

  kv_instances = { for p in local._kv_pairs : p.key => p }

  # Default decoy blob set — no PII, no real creds, no forbidden tokens

  default_decoy_blobs = [
    {
      name    = "employees.csv"
      content = "id,name,department,email\n1,Jane Smith,Finance,jsmith@corp.local\n2,Bob Chen,Engineering,bchen@corp.local\n3,Maria Lopez,Operations,mlopez@corp.local\n"
    },
    {
      name    = "prod-backup.bak"
      content = "PROD_DB_BACKUP v2.3.1 -- internal use only\nChecksum: 9f4e2a1b\nCreated: 2024-11-15\n[snapshot payload omitted]\n"
    },
    {
      name    = "internal-notes.md"
      content = "# Q3 Infrastructure Notes\n- Legacy IAM roles pending cleanup (owner: ops-team)\n- Storage migration blocked on compliance sign-off\n- Rotate service account keys before EOY\n"
    },
    {
      name    = "azure-keys-backup.json"
      content = "{\"note\":\"manual key backup — rotate before EOY\",\"entries\":[{\"name\":\"storage-primary\",\"status\":\"active\"},{\"name\":\"storage-secondary\",\"status\":\"standby\"}]}\n"
    },
  ]

  effective_blobs = length(var.storage_account.decoy_blobs) > 0 ? var.storage_account.decoy_blobs : local.default_decoy_blobs

  # Blob instances: one resource per (storage_instance_key, blob_index)
  sa_blob_instances = var.storage_account.enabled ? merge([
    for sk in keys(local.sa_instances) : {
      for bi, blob in local.effective_blobs :
      "${sk}-blob${bi}" => {
        storage_key  = sk
        blob_name    = blob.name
        blob_content = blob.content
      }
    }
  ]...) : {}

  # Derived names

  sp_prefix = var.service_principal.name_prefix != "" ? var.service_principal.name_prefix : "legacy-svc"
  mi_prefix = var.managed_identity.name_prefix != "" ? var.managed_identity.name_prefix : "legacy-identity"
  sa_prefix = var.storage_account.name_prefix != "" ? var.storage_account.name_prefix : "legacysa"
  kv_prefix = var.key_vault_secret.name_prefix != "" ? var.key_vault_secret.name_prefix : "legacy-kv"

  # KV secret name inside each vault — looks like a real credential name
  kv_secret_name = "storage-account-key"
}

# Random suffixes for globally-unique resource names

resource "random_id" "storage_suffix" {
  for_each    = local.sa_instances
  byte_length = 4
  keepers = {
    name_prefix = local.sa_prefix
    instance    = each.key
  }
}

resource "random_id" "kv_suffix" {
  for_each    = local.kv_instances
  byte_length = 2
  keepers = {
    name_prefix = local.kv_prefix
    instance    = each.key
  }
}

# Used to generate a plausible-looking fake secret value per KV instance
resource "random_id" "kv_secret_token" {
  for_each    = local.kv_instances
  byte_length = 32
  keepers = {
    instance = each.key
  }
}

# Service Principal (App Registration + SP pair)

resource "azuread_application" "decoy" {
  for_each     = local.sp_instances
  display_name = "${local.sp_prefix}-${each.key}"

  # No homepage_url, identifier_uris, redirect_uris — leave unset
  # No app_role, no required_resource_access, no group_membership_claims
  # No certificate credentials, no federated identity credentials
}

resource "azuread_service_principal" "decoy" {
  for_each  = local.sp_instances
  client_id = azuread_application.decoy[each.key].client_id
}

resource "time_offset" "sp_secret_expiry" {
  for_each     = local.sp_secret_instances
  offset_years = var.service_principal.secret_expiry_years
}

resource "azuread_application_password" "decoy" {
  for_each       = local.sp_secret_instances
  display_name   = "api-key-${each.key}"
  application_id = azuread_application.decoy[each.key].id
  end_date       = time_offset.sp_secret_expiry[each.key].rfc3339
}

resource "azuread_conditional_access_policy" "decoy_block" {
  count        = var.service_principal.enabled && var.service_principal.conditional_access_block && var.service_principal.count > 0 ? 1 : 0
  display_name = "${local.sp_prefix}-access-control"
  state        = "enabled"

  conditions {
    applications {
      included_applications = [for k, v in azuread_application.decoy : v.client_id]
    }
    users {
      included_users = ["All"]
    }
    client_app_types = ["all"]
  }

  grant_controls {
    operator          = "OR"
    built_in_controls = ["block"]
  }

  depends_on = [azuread_service_principal.decoy]
}

# User-Assigned Managed Identity

resource "azurerm_user_assigned_identity" "decoy" {
  for_each            = local.mi_instances
  name                = "${local.mi_prefix}-${each.key}"
  resource_group_name = var.resource_group_name
  location            = var.locations[0]
  tags                = local.common_tags

  # Never associated with any compute resource — the free-standing MI is the lure.
  # No azurerm_role_assignment, no azurerm_federated_identity_credential created.
}

# Storage Account + Container + Decoy Blobs

resource "azurerm_storage_account" "decoy" {
  for_each            = local.sa_instances
  name                = "${local.sa_prefix}${random_id.storage_suffix[each.key].hex}"
  resource_group_name = var.resource_group_name
  location            = each.value.location
  account_tier        = "Standard"
  account_replication_type = "LRS"

  # Freely RBAC-reachable from in-tenant principals; no anonymous public read.
  # shared_access_key_enabled = false forces callers through RBAC so every
  # touch is audit-logged. See README for provider auth requirements.
  public_network_access_enabled   = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  min_tls_version                 = "TLS1_2"

  # default_action = Allow (not Deny) — in-tenant data-plane access must land
  # on the account so touches are captured in Azure activity logs.
  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }

  tags = local.common_tags
}

resource "azurerm_storage_container" "decoy" {
  for_each           = local.sa_instances
  name               = "documents"
  storage_account_id = azurerm_storage_account.decoy[each.key].id
}

resource "azurerm_storage_blob" "decoy" {
  for_each               = local.sa_blob_instances
  name                   = each.value.blob_name
  storage_account_name   = azurerm_storage_account.decoy[each.value.storage_key].name
  storage_container_name = azurerm_storage_container.decoy[each.value.storage_key].name
  type                   = "Block"
  source_content         = each.value.blob_content
}

# Key Vault + Secret

resource "azurerm_key_vault" "decoy" {
  for_each            = local.kv_instances
  name                = "${local.kv_prefix}-${random_id.kv_suffix[each.key].hex}"
  resource_group_name = var.resource_group_name
  location            = each.value.location
  tenant_id           = var.tenant_id
  sku_name            = "standard"

  # RBAC-mode — all access control via Azure RBAC, not legacy access policies.
  # The module creates zero role assignments, so no principal can read the
  # secret without the client explicitly granting access.
  rbac_authorization_enabled = true

  # Publicly reachable so in-tenant principals with Key Vault Secrets User
  # can access (and be audit-logged doing so).
  public_network_access_enabled = true

  # Soft-delete is mandatory in azurerm >= 3.0. Purge protection off so
  # terraform destroy works without a 90-day soft-delete window.
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  tags = local.common_tags
}

resource "azurerm_key_vault_secret" "decoy" {
  for_each     = local.kv_instances
  name         = local.kv_secret_name
  key_vault_id = azurerm_key_vault.decoy[each.key].id

  # If the caller supplies a fake_value, use it; otherwise generate a
  # connection-string-shaped placeholder that looks like a real Azure secret.
  value = var.key_vault_secret.fake_value != "" ? var.key_vault_secret.fake_value : (
    "DefaultEndpointsProtocol=https;AccountName=${local.sa_prefix}${random_id.kv_secret_token[each.key].hex};AccountKey=${random_id.kv_secret_token[each.key].b64_std};EndpointSuffix=core.windows.net"
  )

  tags = local.common_tags
}
