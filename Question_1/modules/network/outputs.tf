output "vnet_id" {
  description = "VNet resource ID."
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "VNet name."
  value       = azurerm_virtual_network.this.name
}

output "workload_subnet_id" {
  description = "Workload subnet ID."
  value       = azurerm_subnet.workload.id
}

output "private_endpoint_subnet_id" {
  description = "Private endpoint subnet ID."
  value       = azurerm_subnet.private_endpoints.id
}
