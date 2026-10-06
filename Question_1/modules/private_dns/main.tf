resource "azurerm_private_dns_zone" "this" {
  for_each = var.zones

  name                = each.value
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Link each zone to the VNet so <account>.blob.core.windows.net resolves to the private endpoint IP
# from inside the network. Auto-registration is off: records come from the PE DNS zone groups only.
resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = var.zones

  name                 = "link-${var.name_prefix}-${each.key}"
  private_dns_zone_id  = azurerm_private_dns_zone.this[each.key].id
  virtual_network_id   = var.vnet_id
  registration_enabled = false
  tags                 = var.tags
}
