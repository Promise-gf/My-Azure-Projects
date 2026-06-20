# Enterprise: Serverless Container Apps (Opt-In Phase 11)
resource "azurerm_container_app_environment" "this" {
  count                      = var.enabled ? 1 : 0
  name                       = "cae-finops-${var.name_prefix}-${var.environment}"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  zone_redundancy_enabled    = var.environment == "prod"
  infrastructure_subnet_id   = var.vnet_subnet_id
  tags = var.default_tags
}

resource "azurerm_container_app" "enricher" {
  count                        = var.enabled ? 1 : 0
  name                         = "ca-enricher-${var.name_prefix}-${var.environment}"
  container_app_environment_id = azurerm_container_app_environment.this[0].id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"

  identity { type = "SystemAssigned" }

  registry {
    server = var.acr_login_server
  }

  template {
    container {
      name   = "cost-enricher"
      image  = "${var.acr_login_server}/cost-functions:latest"
      cpu    = 0.5
      memory = "1.0Gi"

      env {
        name  = "FUNCTIONS_WORKER_RUNTIME"
        value = "python"
      }

      env {
        name  = "STORAGE_ACCOUNT_NAME"
        value = var.storage_account_name
      }
    }

    # Scale to zero when no events are processing
    min_replicas = 0 
    max_replicas = 10

    custom_scale_rule {
      name             = "queue-scaling"
      custom_rule_type = "azure-queue"
      metadata = {
        accountName = var.storage_account_name
        queueName   = "cost-events-dlq"
      }
    }
  }
}