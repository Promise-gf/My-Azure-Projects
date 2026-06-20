variable "grafana_major_version" {
  description = "Major version of Grafana for the managed Grafana instance."
  type        = string
}

resource "azurerm_dashboard_grafana" "this" {
  name                    = var.grafana_name
  resource_group_name     = var.resource_group_name
  location                = var.location
  sku                     = var.grafana_sku
  grafana_major_version   = var.grafana_major_version
  identity { type = "SystemAssigned" }

  # Enterprise: Prod ONLY - Block public internet (Access via Private Endpoint only)
  public_network_access_enabled = var.private_endpoint_subnet_id == null

  tags = var.default_tags
}

# Exceptional: Prod ONLY - Private Endpoint for Dashboard viewing
resource "azurerm_private_endpoint" "grafana" {
  count               = var.private_endpoint_subnet_id != null ? 1 : 0
  name                = "pe-grafana-${var.grafana_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "psc-grafana-${var.grafana_name}"
    private_connection_resource_id = azurerm_dashboard_grafana.this.id
    is_manual_connection           = false
    subresource_names              = ["grafana"]
  }
  tags = var.default_tags
}

# RBAC: Grant Grafana access to Data Sources via Managed Identity
resource "azurerm_role_assignment" "log_analytics_reader" {
  scope                = var.log_analytics_workspace_id
  role_definition_name = "Log Analytics Reader"
  principal_id         = azurerm_dashboard_grafana.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "storage_blob_reader" {
  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_dashboard_grafana.this.identity[0].principal_id
}

# Data Sources Provisioned as Code
resource "azapi_resource" "grafana_ds_log_analytics" {
  type      = "Microsoft.Dashboard/grafana/dataSources@2023-09-01"
  name      = "LogAnalyticsDS"
  parent_id = azurerm_dashboard_grafana.this.id
  body = jsonencode({
    properties = {
      dataSourceType = "AzureMonitor"
      connectionDetails = {
        subscriptionId = split("/", var.log_analytics_workspace_id)[2]
        resourceGroup  = split("/", var.log_analytics_workspace_id)[4]
        workspaceName  = split("/", var.log_analytics_workspace_id)[8]
      }
      secrets = { managedIdentity = { clientId = azurerm_dashboard_grafana.this.identity[0].principal_id } }
    }
  })
}

resource "azapi_resource" "grafana_ds_storage" {
  type      = "Microsoft.Dashboard/grafana/dataSources@2023-09-01"
  name      = "ZRSStorageDS"
  parent_id = azurerm_dashboard_grafana.this.id
  body = jsonencode({
    properties = {
      dataSourceType = "AzureBlobStorage"
      connectionDetails = {
        storageAccountName = var.storage_account_name
        containerName      = "enriched-data"
      }
      secrets = { managedIdentity = { clientId = azurerm_dashboard_grafana.this.identity[0].principal_id } }
    }
  })
}