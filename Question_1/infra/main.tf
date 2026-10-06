locals {
  name_prefix = "${var.project}-${var.environment}"

  tags = merge({
    project     = var.project
    environment = var.environment
    managed_by  = "terraform"
  }, var.tags)

  private_dns_zones = {
    blob  = "privatelink.blob.core.windows.net"
    vault = "privatelink.vaultcore.azure.net"
  }
}

# Storage account and Key Vault names are global; a short random suffix keeps them unique
# and avoids clashing with soft-deleted vaults from earlier deployments.
resource "random_string" "suffix" {
  length  = 5
  lower   = true
  upper   = false
  numeric = true
  special = false
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.tags

  lifecycle {
    precondition {
      condition     = contains(var.allowed_locations, var.location)
      error_message = "Location ${var.location} is blocked by the subscription's allowed-regions policy."
    }
  }
}

module "network" {
  source = "../modules/network"

  name_prefix                    = local.name_prefix
  location                       = var.location
  resource_group_name            = azurerm_resource_group.this.name
  address_space                  = var.address_space
  workload_subnet_prefix         = var.workload_subnet_prefix
  private_endpoint_subnet_prefix = var.private_endpoint_subnet_prefix
  tags                           = local.tags
}

module "private_dns" {
  source = "../modules/private_dns"

  name_prefix         = local.name_prefix
  resource_group_name = azurerm_resource_group.this.name
  vnet_id             = module.network.vnet_id
  zones               = local.private_dns_zones
  tags                = local.tags
}

module "storage" {
  source = "../modules/storage"

  name                       = "st${var.project}${var.environment}${random_string.suffix.result}"
  location                   = var.location
  resource_group_name        = azurerm_resource_group.this.name
  replication_type           = var.storage_replication_type
  soft_delete_retention_days = var.storage_soft_delete_days
  private_endpoint_subnet_id = module.network.private_endpoint_subnet_id
  blob_private_dns_zone_id   = module.private_dns.zone_ids["blob"]
  tags                       = local.tags
}

module "key_vault" {
  source = "../modules/key_vault"

  name                       = "kv-${local.name_prefix}-${random_string.suffix.result}"
  location                   = var.location
  resource_group_name        = azurerm_resource_group.this.name
  soft_delete_retention_days = var.key_vault_soft_delete_days
  purge_protection_enabled   = var.key_vault_purge_protection
  private_endpoint_subnet_id = module.network.private_endpoint_subnet_id
  vault_private_dns_zone_id  = module.private_dns.zone_ids["vault"]
  tags                       = local.tags
}

module "identity" {
  source = "../modules/identity"

  name_prefix         = local.name_prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  container_id        = module.storage.container_id
  tags                = local.tags
}
