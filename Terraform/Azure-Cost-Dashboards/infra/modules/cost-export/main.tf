# Push mechanism: Azure Cost Management -> ZRS Storage
resource "azapi_resource" "cost_export" {
  type      = "Microsoft.CostManagement/exports@2023-08-01"
  name      = "export-actual-${var.name_prefix}-${var.environment}"
  parent_id = var.billing_scope_id
  body = jsonencode({
    properties = {
      format = "Csv"
      definition = {
        type      = "ActualCost"
        timeframe = "TheLastMonth"
        dataSet = {
          granularity = "Daily"
          configuration = {
            columns = ["Date", "SubscriptionId", "SubscriptionName", "ResourceGroup", "ResourceType", "ResourceId", "ResourceName", "ServiceName", "MeterCategory", "MeterSubCategory", "Meter", "CostCenter", "Tag", "Quantity", "EffectivePrice", "Cost", "Currency"]
          }
        }
      }
      deliveryInfo = {
        destination = {
          resourceId     = var.storage_account_id
          container      = var.storage_container_name
          rootFolderPath = "actual-costs"
        }
      }
      schedule = {
        status     = "Active"
        recurrence = var.export_recurrence
      }
    }
  })
  tags = var.default_tags
}