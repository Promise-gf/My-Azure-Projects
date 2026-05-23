# This local block acts as a switch statement. 
# Based on the tier_type passed from main.tf, it builds a different list of rules.
locals {
  rules = var.tier_type == "web" ? [
    { name = "AllowHTTPInbound", pri = 100, port = "80", source = "Internet", protocol = "Tcp" },
    { name = "AllowHTTPSInbound", pri = 110, port = "443", source = "Internet", protocol = "Tcp" },
    { name = "AllowMgmt", pri = 200, port = "22", source = var.management_ip, protocol = "Tcp" }
  ] : var.tier_type == "app" ? [
    { name = "AllowWebToApp", pri = 100, port = "8080", source = var.web_cidr, protocol = "Tcp" },
    { name = "AllowVPN", pri = 300, port = "*", source = var.vpn_pool, protocol = "*" },
    { name = "AllowMgmt", pri = 200, port = "22", source = var.management_ip, protocol = "Tcp" }
  ] : var.tier_type == "database" ? [
    { name = "AllowAppToDb", pri = 100, port = "1433", source = var.app_cidr, protocol = "Tcp" },
    { name = "AllowSpokeToDb", pri = 110, port = "1433", source = var.spoke_cidr, protocol = "Tcp" },
    { name = "AllowVPNMgmt", pri = 300, port = "22", source = var.vpn_pool, protocol = "Tcp" }
  ] : [ # Fallback for secondary
    { name = "AllowHubInbound", pri = 100, port = "*", source = var.hub_cidr, protocol = "*" },
    { name = "AllowMgmt", pri = 200, port = "22", source = var.management_ip, protocol = "Tcp" }
  ]
}

resource "azurerm_network_security_group" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  # The dynamic block loops over the list of rules we created above and generates Terraform code for each.
  dynamic "security_rule" {
    for_each = { for r in local.rules : r.name => r }
    content {
      name                       = security_rule.value.name
      priority                   = security_rule.value.pri
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = security_rule.value.protocol
      source_port_range          = "*"
      destination_port_range     = security_rule.value.port
      source_address_prefix      = security_rule.value.source
      destination_address_prefix = "*"
    }
  }
}