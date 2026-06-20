# Enterprise: API Management for Chargeback Showback
resource "azurerm_api_management" "this" {
  name                = "apim-finops-${var.name_prefix}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  publisher_name      = "FinOps Platform"
  publisher_email     = "finops@company.com"
  
  # Enterprise: Consumption tier in Dev (Serverless, pay-per-request)
  # Standard tier in Prod for VNet integration and caching
  sku_name = var.environment == "prod" ? "Standard_1" : "Consumption_0"
  
  tags = var.default_tags
}