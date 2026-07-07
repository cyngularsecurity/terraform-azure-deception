terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # < 5.0: azurerm_storage_blob still uses storage_account_name /
      # storage_container_name, which are removed in v5.
      version = ">= 4.0, < 5.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9"
    }
  }
}
