# ── Log Analytics Workspace ────────────────────────────────────────────────────

resource "azurerm_log_analytics_workspace" "this" {
  name                = "law-${var.name_prefix}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"

  # Enterprise: 90-day hot retention for financial audit compliance
  retention_in_days = 90

  # Enterprise: daily cap to prevent runaway Log Analytics costs
  daily_quota_gb = 10

  tags = var.default_tags
}

# ── Application Insights ───────────────────────────────────────────────────────

resource "azurerm_application_insights" "this" {
  name                = "appi-${var.name_prefix}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  workspace_id        = azurerm_log_analytics_workspace.this.id
  application_type    = "other"
  tags                = var.default_tags
}

# ── Action Group (Self-Healing webhook to Python Function) ─────────────────────
# UPDATED: Replaced Logic App with Webhook to the self_heal_trigger Python Function

resource "azurerm_monitor_action_group" "self_heal" {
  name                = "ag-self-heal-${var.name_prefix}-${var.environment}"
  resource_group_name = var.resource_group_name
  short_name          = "selfheal"

  webhook_receiver {
    name                    = "trigger-self-heal-function"
    service_uri             = var.self_heal_function_url # URL of the Python Function
    use_common_alert_schema = true
  }

  tags = var.default_tags
}

# ── Action Group (Email/Teams alerts) ─────────────────────────────────────────

resource "azurerm_monitor_action_group" "finops_alerts" {
  name                = "ag-finops-${var.name_prefix}-${var.environment}"
  resource_group_name = var.resource_group_name
  short_name          = "finops"

  dynamic "email_receiver" {
    for_each = var.alert_emails
    content {
      name                    = "email-${email_receiver.key}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }

  tags = var.default_tags
}

# ── Alert: Stale Cost Data (26h no ingestion) ─────────────────────────────────

resource "azurerm_monitor_scheduled_query_rules_alert" "stale_cost_data" {
  name                = "alert-stale-cost-${var.name_prefix}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name

  data_source_id = azurerm_log_analytics_workspace.this.id
  description    = "Fires if no cost data has been logged in 26 hours — triggers self-healing Function"
  enabled        = true
  severity       = 1
  frequency      = 60    # every 60 minutes
  time_window    = 1560  # 26 hours in minutes

  query = <<-QUERY
    CostEnrichmentLogs_CL
    | where TimeGenerated > ago(26h)
    | summarize RecordCount = count()
    | where RecordCount == 0
  QUERY

  trigger {
    operator  = "GreaterThan"
    threshold = 0
  }

  action {
    action_group  = [azurerm_monitor_action_group.self_heal.id]
    email_subject = "ALERT: Cost pipeline stale — no data in 26 hours [${var.environment}]"
  }

  tags = var.default_tags
}

# ── Alert: Cost Anomaly (spend velocity >50% above 7-day rolling average) ──────

resource "azurerm_monitor_scheduled_query_rules_alert" "cost_anomaly" {
  name                = "alert-cost-anomaly-${var.name_prefix}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name

  data_source_id = azurerm_log_analytics_workspace.this.id
  description    = "Fires if today's spend is more than 50% above the 7-day rolling average per department"
  enabled        = true
  severity       = 2
  frequency      = 360   # every 6 hours
  time_window    = 10080 # 7 days in minutes

  query = <<-QUERY
    CostEnrichmentLogs_CL
    | where TimeGenerated > ago(7d)
    | summarize
        TodaySpend  = sumif(TotalCost_d, TimeGenerated > ago(1d)),
        SevenDayAvg = avg(TotalCost_d)
      by Department_s
    | extend
        SpendVelocity = iff(
          SevenDayAvg > 0,
          (TodaySpend - SevenDayAvg) / SevenDayAvg * 100,
          0.0
        )
    | where SpendVelocity > 50
    | project Department_s, TodaySpend, SevenDayAvg, SpendVelocity
  QUERY

  trigger {
    operator  = "GreaterThan"
    threshold = 0

    metric_trigger {
      operator            = "GreaterThan"
      threshold           = 0
      metric_trigger_type = "Total"
      metric_column       = "Department_s"
    }
  }

  action {
    action_group  = [azurerm_monitor_action_group.finops_alerts.id]
    email_subject = "ALERT: Spend anomaly — velocity >50% above 7-day avg [${var.environment}]"
    custom_webhook_payload = jsonencode({
      alertType   = "CostAnomaly"
      environment = var.environment
      threshold   = "50%"
    })
  }

  tags = var.default_tags
}