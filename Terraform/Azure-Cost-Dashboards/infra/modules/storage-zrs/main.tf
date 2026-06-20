
 resource "azurerm_storage_account" "this" {
  name                            = var.storage_account_name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = var.account_replication_type
  min_tls_version                 = var.min_tls_version
  allow_nested_items_to_be_public = false
  https_traffic_only_enabled      = true

  # Enterprise: Prod ONLY - Block public access
  public_network_access_enabled   = var.private_endpoint_subnet_id == null
  network_rules {
    default_action             = var.private_endpoint_subnet_id == null ? "Allow" : "Deny"
    bypass                     = "AzureServices"
  }

  blob_properties {
    versioning_enabled = true
    delete_retention_policy { days = 30 }
  }
  tags = var.default_tags
}

resource "azurerm_storage_container" "cost_exports" {
  name                 = "cost-exports"
  storage_account_id   = azurerm_storage_account.this.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "enriched_data" {
  name                 = "enriched-data"
  storage_account_id   = azurerm_storage_account.this.id
  container_access_type = "private"
}

resource "azurerm_storage_queue" "event_grid_dlq" {
  name                = "cost-events-dlq"
  storage_account_id  = azurerm_storage_account.this.id
}

# Exceptional: Prod ONLY - Private Endpoint for Data (Zero Trust Ingress)
resource "azurerm_private_endpoint" "blob" {
  count               = var.private_endpoint_subnet_id != null ? 1 : 0
  name                = "pe-stblob-${var.storage_account_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "psc-stblob-${var.storage_account_name}"
    private_connection_resource_id = azurerm_storage_account.this.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }
  tags = var.default_tags
}