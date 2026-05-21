locals {
  standard_subnets = [
    for k, v in var.subnets : {
      name   = "snet-${k}"
      cidr   = v
      nsg_id = lookup(var.nsg_ids, k, null)
    }
  ]

  conditional_subnets = concat(
    var.deploy_vpn      ? [{ name = "GatewaySubnet",       cidr = var.gateway_cidr,  nsg_id = null }] : [],
    var.deploy_bastion  ? [{ name = "AzureBastionSubnet",  cidr = var.bastion_cidr,  nsg_id = null }] : [],
    var.deploy_firewall ? [{ name = "AzureFirewallSubnet", cidr = var.firewall_cidr, nsg_id = null }] : []
  )

  all_subnets = { for s in concat(local.standard_subnets, local.conditional_subnets) : s.name => s }
}

resource "azurerm_virtual_network" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.address_space]
  tags                = var.tags
}

resource "azurerm_subnet" "this" {
  for_each = local.all_subnets

  name                 = each.value.name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [each.value.cidr]

  service_endpoints = lookup(var.service_endpoints, each.value.name, [])
}

# FIX: iterate var.nsg_ids directly — keys are static strings, not apply-time values
resource "azurerm_subnet_network_security_group_association" "this" {
  for_each = var.nsg_ids

  subnet_id                 = azurerm_subnet.this["snet-${each.key}"].id
  network_security_group_id = each.value
}