output "key_vault_id" {
  description = "Key Vault ID."
  value       = azurerm_key_vault.this.id
}

output "key_vault_uri" {
  description = "Key Vault URI (resolves privately inside the VNet)."
  value       = azurerm_key_vault.this.vault_uri
}

output "private_endpoint_ip" {
  description = "Private IP of the vault private endpoint."
  value       = azurerm_private_endpoint.vault.private_service_connection[0].private_ip_address
}
