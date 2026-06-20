output "vnet_id" {
  description = "Virtual Network resource ID"
  value       = azurerm_virtual_network.this.id
}

output "function_subnet_id" {
  description = "Function App subnet ID for VNet integration"
  value       = azurerm_subnet.function.id
}

output "pe_subnet_id" {
  description = "Private Endpoint subnet ID"
  value       = azurerm_subnet.private_endpoints.id
}

output "pe_nsg_id" {
  description = "Private Endpoint NSG resource ID"
  value       = azurerm_network_security_group.pe_nsg.id
}

output "vnet_id"                  { value = azurerm_virtual_network.this.id }
output "function_subnet_id"       { value = azurerm_subnet.function.id }
output "private_endpoint_subnet_id" { value = azurerm_subnet.private_endpoints.id }