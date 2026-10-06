output "resource_group_name" {
  description = "Resource group name."
  value       = azurerm_resource_group.this.name
}

output "vnet_id" {
  description = "VNet ID."
  value       = module.network.vnet_id
}

output "storage_account_name" {
  description = "Storage account name."
  value       = module.storage.storage_account_name
}

output "storage_private_ip" {
  description = "Private IP the storage account resolves to inside the VNet."
  value       = module.storage.private_endpoint_ip
}

output "key_vault_uri" {
  description = "Key Vault URI."
  value       = module.key_vault.key_vault_uri
}

output "key_vault_private_ip" {
  description = "Private IP the Key Vault resolves to inside the VNet."
  value       = module.key_vault.private_endpoint_ip
}

output "managed_identity_client_id" {
  description = "Client ID of the blob-reader managed identity."
  value       = module.identity.client_id
}
