resource "azurerm_private_dns_zone" "this" {
  name                = var.dns_zone_name
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# FIX: static map keys instead of toset() of unknown IDs
resource "azurerm_private_dns_zone_virtual_network_link" "links" {
  for_each              = { for idx, id in var.vnet_ids : "link-${idx}" => id }
  name                  = "dns-link-${each.key}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.this.name
  virtual_network_id    = each.value
  registration_enabled  = false
}

resource "azurerm_private_endpoint" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "pec-${var.name}"
    private_connection_resource_id = var.target_resource_id
    is_manual_connection           = false
    subresource_names              = [var.group_id]
  }
}

resource "azurerm_private_dns_a_record" "this" {
  name                = var.target_resource_name
  zone_name           = azurerm_private_dns_zone.this.name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = [azurerm_private_endpoint.this.private_service_connection[0].private_ip_address]
}