output "grafana_endpoint" { value = azurerm_dashboard_grafana.this.endpoint }
output "principal_id" { value = azurerm_dashboard_grafana.this.identity[0].principal_id }
output "grafana_endpoint" { value = azurerm_dashboard_grafana.this.endpoint }
output "principal_id"     { value = azurerm_dashboard_grafana.this.identity[0].principal_id }