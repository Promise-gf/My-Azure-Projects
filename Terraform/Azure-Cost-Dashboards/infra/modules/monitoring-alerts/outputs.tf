output "workspace_id" {
  description = "Log Analytics Workspace resource ID"
  value       = azurerm_log_analytics_workspace.this.id
}

output "workspace_customer_id" {
  description = "Log Analytics Workspace customer ID (used by Python functions)"
  value       = azurerm_log_analytics_workspace.this.workspace_id
}

output "app_insights_connection_string" {
  description = "Application Insights connection string (used by Function App)"
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "app_insights_instrumentation_key" {
  description = "Application Insights instrumentation key"
  value       = azurerm_application_insights.this.instrumentation_key
  sensitive   = true
}

output "action_group_self_heal_id" {
  description = "Resource ID of the self-healing action group"
  value       = azurerm_monitor_action_group.self_heal.id
}

output "action_group_finops_id" {
  description = "Resource ID of the FinOps alerts action group"
  value       = azurerm_monitor_action_group.finops_alerts.id
}
output "app_insights_connection_string" { value = azurerm_application_insights.this.connection_string }
output "log_analytics_workspace_id"     { value = azurerm_log_analytics_workspace.this.id }