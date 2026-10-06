output "identity_id" {
  description = "Managed identity resource ID (attach to the workload)."
  value       = azurerm_user_assigned_identity.this.id
}

output "client_id" {
  description = "Client ID the application uses to request tokens."
  value       = azurerm_user_assigned_identity.this.client_id
}

output "principal_id" {
  description = "Object ID of the identity."
  value       = azurerm_user_assigned_identity.this.principal_id
}
