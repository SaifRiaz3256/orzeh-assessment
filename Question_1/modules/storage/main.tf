# tflint-ignore: azurerm_resources_missing_prevent_destroy # prevent_destroy cannot vary per env and dev must be destroyable; prod relies on soft delete/versioning/purge protection.
resource "azurerm_storage_account" "this" {
  #checkov:skip=CKV_AZURE_33:Queue service is not used (blob only); queue logging would need data-plane access, which is deliberately unavailable.
  #checkov:skip=CKV2_AZURE_1:Platform-managed keys + infrastructure (double) encryption; customer-managed keys in Key Vault are a README "Before production" item.
  #checkov:skip=CKV_AZURE_59:False positive - check reads the deprecated public_network_access_enabled; public_network_access = "Disabled" is set below (azurerm v5).
  name                     = var.name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = var.replication_type
  tags                     = var.tags

  # No public endpoint: reachable only through the private endpoint below.
  public_network_access = "Disabled"

  # Entra ID (RBAC) only - no account keys or SAS tokens.
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  local_user_enabled              = false

  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  allow_nested_items_to_be_public   = false
  cross_tenant_replication_enabled  = false
  infrastructure_encryption_enabled = true
  allowed_copy_scope                = "PrivateLink"

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = var.soft_delete_retention_days
    }

    container_delete_retention_policy {
      days = var.soft_delete_retention_days
    }
  }
}

# Created through the management plane (storage_account_id), so it works even though
# the data plane is unreachable from outside the VNet.
# tflint-ignore: azurerm_resources_missing_prevent_destroy # prevent_destroy cannot vary per env and dev must be destroyable; prod relies on soft delete/versioning/purge protection.
resource "azurerm_storage_container" "this" {
  #checkov:skip=CKV2_AZURE_21:Blob read logging needs diagnostic settings + Log Analytics; listed under README "Before production".
  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

resource "azurerm_private_endpoint" "blob" {
  name                          = "pe-${var.name}-blob"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  subnet_id                     = var.private_endpoint_subnet_id
  custom_network_interface_name = "nic-pe-${var.name}-blob"
  tags                          = var.tags

  private_service_connection {
    name                           = "psc-${var.name}-blob"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  # Creates the A record <account>.privatelink.blob.core.windows.net -> PE private IP.
  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.blob_private_dns_zone_id]
  }
}
