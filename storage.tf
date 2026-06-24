resource "random_id" "storage_suffix" {
  for_each    = local.sa_instances
  byte_length = 4
  keepers = {
    name_prefix = local.sa_prefix
    instance    = each.key
  }
}

resource "azurerm_storage_account" "decoy" {
  for_each                 = local.sa_instances
  name                     = "${local.sa_prefix}${random_id.storage_suffix[each.key].hex}"
  resource_group_name      = var.resource_group_name
  location                 = each.value.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  public_network_access_enabled   = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  min_tls_version                 = "TLS1_2"
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
