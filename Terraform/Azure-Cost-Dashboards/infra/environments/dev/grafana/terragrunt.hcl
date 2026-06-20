include "root"      { path = find_in_parent_folders() }
include "envcommon" { path = "${dirname(find_in_parent_folders())}/_envcommon/grafana.hcl" expose = true }
include "env"       { path = "${dirname(find_in_parent_folders())}/env.hcl" expose = true }
dependency "resource_group" { config_path = "../resource-group"; mock_outputs = { name = "mock-rg", location = "eastus" } }
dependency "storage"        { config_path = "../storage-zrs";    mock_outputs = { id = "/sub/mock/st", name = "mockst" } }
dependency "monitor"        { config_path = "../monitoring";     mock_outputs = { log_analytics_workspace_id = "/sub/mock/la" } }
inputs = {
  resource_group_name        = dependency.resource_group.outputs.name
  location                   = dependency.resource_group.outputs.location
  grafana_name               = "grafana-${include.env.locals.name_prefix}-${include.env.locals.env}"
  tenant_id                  = get_env("ARM_TENANT_ID")
  log_analytics_workspace_id = dependency.monitor.outputs.log_analytics_workspace_id
  storage_account_id         = dependency.storage.outputs.id
  storage_account_name       = dependency.storage.outputs.name
  environment                = include.env.locals.env
}