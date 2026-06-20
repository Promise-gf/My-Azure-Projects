# Enterprise: Data Collection Endpoint (The ingestion URL)
resource "azurerm_monitor_data_collection_endpoint" "this" {
  name                        = "dce-finops-${var.name_prefix}-${var.environment}"
  resource_group_name         = var.resource_group_name
  location                    = var.location
  kind                        = "Linux"
  public_network_access_enabled = true # Set to false in Prod if using Private Link
  
  tags = var.default_tags
}

# Enterprise: Data Collection Rule (The schema and routing)
resource "azurerm_monitor_data_collection_rule" "this" {
  name                        = "dcr-finops-${var.name_prefix}-${var.environment}"
  resource_group_name         = var.resource_group_name
  location                    = var.location
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.this.id
  kind                        = "Direct"

  destinations {
    log_analytics {
      name                  = "loganalytics-dcr"
      workspace_resource_id = var.log_analytics_workspace_id
    }
  }

  data_flow {
    streams       = ["Custom-CostEnrichmentLogs_CL"]
    destinations  = ["loganalytics-dcr"]
    output_stream = "Custom-CostEnrichmentLogs_CL"
    transform_kql = "source"
  }

  stream_declaration {
    stream_name = "Custom-CostEnrichmentLogs_CL"

    column {
      name = "TimeGenerated"
      type = "datetime"
    }
    column {
      name = "Department_s"
      type = "string"
    }
    column {
      name = "ResourceName_s"
      type = "string"
    }
    column {
      name = "TotalCost_d"
      type = "real"
    }
    column {
      name = "Environment_s"
      type = "string"
    }
  }

  tags = var.default_tags
}
# Enterprise: RBAC - Grant Function App rights to push to DCR
resource "azurerm_role_assignment" "dcr_publisher" {
  scope                = azurerm_monitor_data_collection_rule.this.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = var.function_principal_id
}