output "dce_endpoint" { value = azurerm_monitor_data_collection_endpoint.this.logs_ingestion_endpoint }
output "dcr_immutable_id" { value = azurerm_monitor_data_collection_rule.this.immutable_id }
output "stream_name" { value = "Custom-CostEnrichmentLogs_CL" }