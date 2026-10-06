data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "state" {
  name     = var.state_resource_group_name
  location = var.location
  tags     = var.tags
}

# Remote state backend. Locking is a native blob lease on each state file.
resource "azurerm_storage_account" "state" {
  #checkov:skip=CKV_AZURE_33:Queue service is not used (blob only); queue logging would need data-plane access, which is deliberately unavailable.
  #checkov:skip=CKV2_AZURE_1:Platform-managed keys + infrastructure (double) encryption; customer-managed keys in Key Vault are a README "Before production" item.
  #checkov:skip=CKV_AZURE_59:Public endpoint required by GitHub-hosted runners; access is Entra ID + RBAC only (no keys). Production: private endpoint + self-hosted runners.
  #checkov:skip=CKV2_AZURE_33:Same reason - no private network path from GitHub-hosted runners.
  name                     = var.state_storage_account_name
  resource_group_name      = azurerm_resource_group.state.name
  location                 = azurerm_resource_group.state.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "GZRS"
  tags                     = var.tags

  # Public endpoint is kept because GitHub-hosted runners have no private network path.
  # Access still requires Entra ID + RBAC (no keys). Production: private endpoint + self-hosted runners.
  public_network_access = "Enabled"

  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  local_user_enabled                = false
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  allow_nested_items_to_be_public   = false
  cross_tenant_replication_enabled  = false
  infrastructure_encryption_enabled = true

  lifecycle {
    prevent_destroy = true
  }

  # Recover from a bad write or accidental delete of a state file.
  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }
}

resource "azurerm_storage_container" "state" {
  #checkov:skip=CKV2_AZURE_21:Blob read logging needs diagnostic settings + Log Analytics; listed under README "Before production".
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"

  lifecycle {
    prevent_destroy = true
  }
}

# Guard against accidental deletion of the state account.
resource "azurerm_management_lock" "state" {
  name       = "lock-tfstate"
  scope      = azurerm_storage_account.state.id
  lock_level = "CanNotDelete"
  notes      = "Holds Terraform state for all environments."
}

# The engineer running Terraform locally (az login) also needs data-plane access to state.
resource "azurerm_role_assignment" "state_operator" {
  scope                = azurerm_storage_container.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}
