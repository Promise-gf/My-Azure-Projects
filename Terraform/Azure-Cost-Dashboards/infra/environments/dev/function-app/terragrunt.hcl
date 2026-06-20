include "root"      { path = find_in_parent_folders() }
include "envcommon" { path = "${dirname(find_in_parent_folders())}/_envcommon/function-app.hcl" expose = true }
include "env"       { path = "${dirname(find_in_parent_folders())}/env.hcl" expose = true }
dependency "resource_group" { config_path = "../resource-group"; mock_outputs = { name = "mock-rg", location = "eastus" } }
dependency "storage"        { config_path = "../storage-zrs";    mock_outputs = { name = "mockst", id = "/sub/mock/st" } }
dependency "key_vault"      { config_path = "../key-vault";     mock_outputs = { name = "mock-kv", id = "/sub/mock/kv" } }
dependency "monitor"        { config_path = "../monitoring";    mock_outputs = { app_insights_connection_string = "mock-cs" } }
inputs = {
  resource_group_name            = dependency.resource_group.outputs.name
  location                       = dependency.resource_group.outputs.location
  function_app_name              = "func-${include.env.locals.name_prefix}-${include.env.locals.env}"
  storage_account_name           = dependency.storage.outputs.name
  storage_account_id             = dependency.storage.outputs.id
  key_vault_name                 = dependency.key_vault.outputs.name
  key_vault_id                   = dependency.key_vault.outputs.id
  app_insights_connection_string = dependency.monitor.outputs.app_insights_connection_string
  app_service_plan_sku           = include.env.locals.function_sku
  environment                    = include.env.locals.env
  subscription_id                = get_env("ARM_SUBSCRIPTION_ID")
  acr_login_server               = "acr${include.env.locals.name_prefix}${include.env.locals.env}.azurecr.io"
  container_image_name           = "cost-functions"
  container_image_tag            = "latest"
  app_settings = {
    STORAGE_ACCOUNT_NAME = dependency.storage.outputs.name
    KEY_VAULT_NAME       = dependency.key_vault.outputs.name
    ENVIRONMENT          = include.env.locals.env
    MONTHLY_BUDGET_USD   = tostring(include.env.locals.monthly_budget)
  }
}