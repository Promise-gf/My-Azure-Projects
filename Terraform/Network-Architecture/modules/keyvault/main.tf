resource "azurerm_key_vault" "this" {
  name                        = var.name
  location                    = var.location
  resource_group_name         = var.resource_group_name
  tenant_id                   = var.tenant_id
  sku_name                    = "standard"
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  tags                        = var.tags

  # Automatically grants the person running Terraform full access to secrets.
  # (In a real enterprise, this object_id would be a break-glass admin group).
  access_policy {
    tenant_id = var.tenant_id
    object_id = var.object_id
    secret_permissions = [
      "Get", "List", "Set", "Delete"
    ]
  }
}