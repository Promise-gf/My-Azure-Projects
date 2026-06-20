variable "name" { type = string }
variable "location" { type = string }
variable "default_tags" {
  type = map(string)
  default = {}
}
output "name"     { value = azurerm_resource_group.this.name }
output "location" { value = azurerm_resource_group.this.location }
output "id"       { value = azurerm_resource_group.this.id }