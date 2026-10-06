resource "azurerm_user_assigned_identity" "this" {
  name                = "id-${var.name_prefix}-blob-reader"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Least privilege: read-only data access, scoped to the single container -
# not the account, resource group or subscription. No control-plane or Key Vault rights.
resource "azurerm_role_assignment" "blob_reader" {
  scope                = var.container_id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
  principal_type       = "ServicePrincipal"
  description          = "Read-only blob access for the ${var.name_prefix} application."
}
