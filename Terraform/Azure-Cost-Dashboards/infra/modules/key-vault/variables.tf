variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "key_vault_name" { type = string }
variable "tenant_id" { type = string }
variable "default_tags" {
  type = map(string)
  default = {}
}
# Exceptional: Prod Private Endpoint
variable "private_endpoint_subnet_id" {
  type    = string
  default = null
}
output "name"     { value = azurerm_key_vault.this.name }
output "id"       { value = azurerm_key_vault.this.id }
output "vault_uri" { value = azurerm_key_vault.this.vault_uri }