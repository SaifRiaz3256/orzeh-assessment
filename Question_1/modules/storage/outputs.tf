output "storage_account_id" {
  description = "Storage account ID."
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "Storage account name."
  value       = azurerm_storage_account.this.name
}

output "container_id" {
  description = "Resource Manager ID of the blob container (used as the RBAC scope)."
  value       = azurerm_storage_container.this.id
}

output "private_endpoint_ip" {
  description = "Private IP of the blob private endpoint."
  value       = azurerm_private_endpoint.blob.private_service_connection[0].private_ip_address
}
