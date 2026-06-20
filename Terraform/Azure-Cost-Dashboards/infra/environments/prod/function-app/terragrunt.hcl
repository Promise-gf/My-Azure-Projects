include "root"      { path = find_in_parent_folders() }
include "envcommon" { path = "${dirname(find_in_parent_folders())}/_envcommon/function-app.hcl" expose = true }
include "env"       { path = "${dirname(find_in_parent_folders())}/env.hcl" expose = true }

# ── Dependencies ──────────────────────────────────────────────────
dependency "resource_group" { 
  config_path = "../resource-group"
  mock_outputs = { name = "mock-rg", location = "eastus" }
}

dependency "storage" { 
  config_path = "../storage-zrs"
  mock_outputs = { name = "mockst", id = "/sub/mock/st" }
}

dependency "key_vault" { 
  config_path = "../key-vault"
  mock_outputs = { name = "mock-kv", id = "/sub/mock/kv" }
}

dependency "monitoring" { 
  config_path = "../monitoring"
  mock_outputs = { 
    app_insights_connection_string = "mock-cs"
    self_heal_function_url        = "https://mock.azurewebsites.net/api/self-heal"
  }
}

dependency "vnet" { 
  config_path = "../vnet"
  mock_outputs = { 
    function_subnet_id = "/sub/mock/vnet/snet-func" 
  }
}

dependency "dcr" { 
  config_path = "../dcr"
  mock_outputs = { 
    dce_endpoint      = "https://mock.ingestion.monitor.azure.com"
    dcr_immutable_id  = "dcr-mock-id"
    stream_name       = "Custom-CostEnrichmentLogs_CL"
  }
}

dependency "auto_remediation" { 
  config_path = "../auto-remediation"
  mock_outputs = { 
    auto_stop_webhook_url = "https://mock.logic.azure.com:443/workflows/auto-stop/triggers/manual/paths/invoke?api-version=2016-10-01"
  }
}

# ── Inputs ────────────────────────────────────────────────────────
inputs = {
  resource_group_name            = dependency.resource_group.outputs.name
  location                       = dependency.resource_group.outputs.location
  function_app_name              = "func-${include.env.locals.name_prefix}-${include.env.locals.env}"
  storage_account_name           = dependency.storage.outputs.name
  storage_account_id             = dependency.storage.outputs.id
  key_vault_name                 = dependency.key_vault.outputs.name
  key_vault_id                   = dependency.key_vault.outputs.id
  app_insights_connection_string = dependency.monitoring.outputs.app_insights_connection_string
  
  # Enterprise: Prod SKU (EP2) defined in env.hcl
  app_service_plan_sku           = include.env.locals.function_sku
  
  # This variable triggers Terraform to enforce Prod security rules
  environment                    = include.env.locals.env
  
  subscription_id                = get_env("ARM_SUBSCRIPTION_ID")
  acr_login_server               = "acr${include.env.locals.name_prefix}${include.env.locals.env}.azurecr.io"
  container_image_name           = "cost-functions"
  # In Prod, pin to a specific SHA tag, not 'latest'
  container_image_tag            = "latest" 

  # ── Zero Trust Networking (Prod Only) ─────────────────────────
  # Forces the Function App to route all egress traffic through the corporate VNet
  vnet_subnet_id                 = dependency.vnet.outputs.function_subnet_id

  # ── DCR Ingestion Config ─────────────────────────────────────
  dcr_endpoint                   = dependency.dcr.outputs.dce_endpoint
  dcr_immutable_id               = dependency.dcr.outputs.dcr_immutable_id
  dcr_stream_name                = dependency.dcr.outputs.stream_name

  # ── App Settings (Environment Variables) ─────────────────────
  app_settings = {
    # Core Config
    STORAGE_ACCOUNT_NAME     = dependency.storage.outputs.name
    KEY_VAULT_NAME           = dependency.key_vault.outputs.name
    ENVIRONMENT              = include.env.locals.env
    AZURE_SUBSCRIPTION_ID    = get_env("ARM_SUBSCRIPTION_ID")
    MONTHLY_BUDGET_USD       = tostring(include.env.locals.monthly_budget)
    
    # Azure Monitor DCR (Structured Logging)
    AZURE_MONITOR_DCE_ENDPOINT     = dependency.dcr.outputs.dce_endpoint
    AZURE_MONITOR_DCR_IMMUTABLE_ID = dependency.dcr.outputs.dcr_immutable_id
    AZURE_MONITOR_STREAM_NAME      = dependency.dcr.outputs.stream_name
    
    # Phase 9: Auto-Remediation Webhook
    AUTO_STOP_WEBHOOK_URL = dependency.auto_remediation.outputs.auto_stop_webhook_url
    
    # Phase 9: Self-Healing Webhook (Triggered by Azure Monitor)
    SELF_HEAL_FUNCTION_URL = dependency.monitoring.outputs.self_heal_function_url
  }
}