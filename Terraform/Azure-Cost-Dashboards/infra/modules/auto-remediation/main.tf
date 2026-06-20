# Enterprise: FinOps Action - Auto-Stop Runbook
resource "azurerm_automation_account" "this" {
  name                = "aa-finops-${var.name_prefix}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "Basic"
  tags = var.default_tags
}

# The Runbook that actually stops the resources
resource "azurerm_automation_runbook" "stop_resources" {
  name                    = "Stop-OverBudgetResources"
  location                = var.location
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.this.name
  log_verbose             = true
  log_progress            = true
  runbook_type            = "PowerShell" # PowerShell is native for Azure Resource Graph
  
  # Enterprise: Only stop resources tagged with the specific Department AND Environment != Production
  content = <<PS1
  param (
      [string]$DepartmentName
  )
  $resources = Search-AzGraph -Query "where tags['Department'] == '$DepartmentName' and tags['Environment'] != 'production' | project id, type"
  foreach ($res in $resources) {
      if ($res.type -eq 'Microsoft.Compute/virtualMachines') {
          Stop-AzVM -ResourceId $res.id -Force -NoWait
          Write-Output "Stopped VM: $($res.id)"
      }
      elseif ($res.type -eq 'Microsoft.Web/sites') {
          # Scale down to Free tier (F1) if over budget
          # Logic can be expanded here
          Write-Output "Flagged WebApp for scale down: $($res.id)"
      }
  }
  PS1
}

# Logic App to bridge the Alert -> Runbook gap
resource "azurerm_logic_app_workflow" "auto_stop" {
  name                = "la-auto-stop-${var.name_prefix}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  identity { type = "SystemAssigned" }
  tags = var.default_tags
}

resource "azurerm_logic_app_trigger_http_request" "auto_stop_trigger" {
  name         = "manual"
  logic_app_id = azurerm_logic_app_workflow.auto_stop.id
  schema = jsonencode({
    type = "object"
    properties = {
      department = { type = "string" }
      severity   = { type = "string" }
    }
  })
}

resource "azurerm_logic_app_action_custom" "start_runbook" {
  name         = "Start-Runbook"
  logic_app_id = azurerm_logic_app_workflow.auto_stop.id
  body = jsonencode({
    type = "ApiConnection"
    inputs = {
      host   = { connection = { name = "@parameters('$connections')['azureautomation']['connectionId']" } }
      method = "post"
      path   = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.Automation/automationAccounts/${azurerm_automation_account.this.name}/jobs?api-version=2023-11-01"
      body   = {
        properties = {
          runbook = { name = azurerm_automation_runbook.stop_resources.name }
          parameters = { DepartmentName = "@triggerBody()['department']" }
        }
      }
    }
    runAfter = {}
  })
}