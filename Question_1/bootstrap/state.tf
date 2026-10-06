data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "state" {
  name     = var.state_resource_group_name
  location = var.location
  tags     = var.tags
}

# Remote state backend. Locking is a native blob lease on each state file.
# Accepted (Trivy): AZU-0012 public endpoint is required by GitHub-hosted runners; access is Entra ID + RBAC
# only (shared keys disabled). Production: private endpoint + self-hosted runners.
# Accepted (Trivy): AZU-0057 logging needs diagnostic settings + Log Analytics; AZU-0060 customer-managed keys.
# Both are listed under README "Before production".
#trivy:ignore:AZU-0012
#trivy:ignore:AZU-0057
#trivy:ignore:AZU-0060
resource "azurerm_storage_account" "state" {
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
