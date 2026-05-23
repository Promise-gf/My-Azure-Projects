output "id" {
  value = azurerm_virtual_network.this.id
}

output "name" {
  value = azurerm_virtual_network.this.name
}

# References the actual azurerm_subnet resources instead of the vnet inline subnet block
output "subnet_ids" {
  value = { for k, v in azurerm_subnet.this : k => v.id }
}