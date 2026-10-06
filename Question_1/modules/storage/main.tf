# Accepted (Trivy): AZU-0057 logging needs diagnostic settings + Log Analytics; AZU-0060 customer-managed keys.
# Both are listed under README "Before production".
# tflint: prevent_destroy cannot vary per env and dev must be destroyable; prod relies on soft delete, versioning and purge protection.
#trivy:ignore:AZU-0057
#trivy:ignore:AZU-0060
resource "azurerm_storage_account" "this" { # tflint-ignore: azurerm_resources_missing_prevent_destroy
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
# tflint: prevent_destroy cannot vary per env and dev must be destroyable; prod relies on soft delete, versioning and purge protection.
resource "azurerm_storage_container" "this" { # tflint-ignore: azurerm_resources_missing_prevent_destroy
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
