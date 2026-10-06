data "azurerm_client_config" "current" {}

# tflint: prevent_destroy cannot vary per env and dev must be destroyable; prod relies on soft delete, versioning and purge protection.
resource "azurerm_key_vault" "this" { # tflint-ignore: azurerm_resources_missing_prevent_destroy
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  tags                = var.tags

  # Azure RBAC instead of access policies: access is granted with role assignments, auditable in one place.
  rbac_authorization_enabled = true

  public_network_access_enabled = false
  soft_delete_retention_days    = var.soft_delete_retention_days
  purge_protection_enabled      = var.purge_protection_enabled

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
  }
}

resource "azurerm_private_endpoint" "vault" {
  name                          = "pe-${var.name}-vault"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  subnet_id                     = var.private_endpoint_subnet_id
  custom_network_interface_name = "nic-pe-${var.name}-vault"
  tags                          = var.tags

  private_service_connection {
    name                           = "psc-${var.name}-vault"
    private_connection_resource_id = azurerm_key_vault.this.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.vault_private_dns_zone_id]
  }
}
