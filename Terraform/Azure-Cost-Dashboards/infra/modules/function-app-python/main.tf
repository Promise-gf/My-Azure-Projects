resource "azurerm_service_plan" "this" {
  name                = "plan-${var.function_app_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Linux"
  sku_name            = var.app_service_plan_sku
  
  # Enterprise: Prod ONLY - Spread across Availability Zones
  zone_balancing_enabled = var.environment == "prod"
}
resource "azurerm_linux_function_app" "this" {
  name                          = var.function_app_name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  service_plan_id               = azurerm_service_plan.this.id
  storage_account_name          = var.storage_account_name
  storage_uses_managed_identity = true
  https_only                    = true
  virtual_network_subnet_id     = var.vnet_subnet_id
  public_network_access_enabled = var.environment != "prod"

  identity { type = "SystemAssigned" }

  site_config {
    application_stack {
      docker {
        registry_url = var.acr_login_server
        image_name   = var.container_image_name
        image_tag    = var.container_image_tag
      }
    }
    always_on = var.environment == "prod"

    health_check_path = "/api/health"
  }

  # Single merged app_settings block with ALL environment variables
  app_settings = merge(var.app_settings, {
    FUNCTIONS_WORKER_RUNTIME              = "python"
    APPLICATIONINSIGHTS_CONNECTION_STRING = var.app_insights_connection_string
    AZURE_MONITOR_DCE_ENDPOINT            = var.dcr_endpoint
    AZURE_MONITOR_DCR_IMMUTABLE_ID        = var.dcr_immutable_id
    AZURE_MONITOR_STREAM_NAME             = var.dcr_stream_name
  })

  tags = var.default_tags
}

# ── RBAC ──────────────────────────────────────────────────────────────────────

resource "azurerm_role_assignment" "storage_blob" {
  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "storage_queue" {
  scope                = var.storage_account_id
  role_definition_name = "Storage Queue Data Message Processor"
  principal_id         = azurerm_linux_function_app.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "cost_reader" {
  scope                = "/subscriptions/${var.subscription_id}"
  role_definition_name = "Cost Management Reader"
  principal_id         = azurerm_linux_function_app.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "kv_secrets" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_function_app.this.identity[0].principal_id
}