resource "azurerm_key_vault" "this" {
  name                        = var.key_vault_name
  resource_group_name         = var.resource_group_name
  location                    = var.location
  tenant_id                   = var.tenant_id
  sku_name                    = "standard"
  purge_protection_enabled    = true
  rbac_authorization_enabled  = true
  soft_delete_retention_days  = 90
  
  # Enterprise: Prod ONLY - Block public access
  public_network_access_enabled = var.private_endpoint_subnet_id == null
  network_acls {
    default_action = var.private_endpoint_subnet_id == null ? "Allow" : "Deny"
    bypass         = "AzureServices"
  }
  
  tags = var.default_tags
}

# Exceptional: Prod ONLY - Private Endpoint for Zero Trust access to secrets
resource "azurerm_private_endpoint" "kv" {
  count               = var.private_endpoint_subnet_id != null ? 1 : 0
  name                = "pe-kv-${var.key_vault_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "psc-kv-${var.key_vault_name}"
    private_connection_resource_id = azurerm_key_vault.this.id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }
  tags = var.default_tags
}