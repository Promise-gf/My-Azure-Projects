output "id" { value = azurerm_linux_function_app.this.id }
output "principal_id" { value = azurerm_linux_function_app.this.identity[0].principal_id }
output "id"                       { value = azurerm_linux_function_app.this.id }
output "principal_id"             { value = azurerm_linux_function_app.this.identity[0].principal_id }
output "default_hostname"         { value = azurerm_linux_function_app.this.default_hostname }

# Critical for Monitor Action Group Webhook
output "self_heal_function_url" {
  value = "https://${azurerm_linux_function_app.this.default_hostname}/api/self-heal?code=${azurerm_linux_function_app.this.default_hostname}"
  # Note: In production, you would securely fetch the function key via azapi or azurerm_function_app_function_keys
}