include "root"      { path = find_in_parent_folders() }
include "envcommon" { path = "${dirname(find_in_parent_folders())}/_envcommon/monitor.hcl" expose = true }
include "env"       { path = "${dirname(find_in_parent_folders())}/env.hcl" expose = true }
dependency "resource_group" { config_path = "../resource-group"; mock_outputs = { name = "mock-rg", location = "eastus", id = "/sub/mock" } }
dependency "storage"        { config_path = "../storage-zrs";    mock_outputs = { id = "/sub/mock/st" } }
dependency "logic_app"      { config_path = "../self-healing-logic-app"; mock_outputs = { id = "/sub/mock/la", callback_url = "https://mock.logic.azure.com" } }
inputs = {
  resource_group_name    = dependency.resource_group.outputs.name
  location               = dependency.resource_group.outputs.location
  name_prefix            = include.env.locals.name_prefix
  environment            = include.env.locals.env
  storage_account_id     = dependency.storage.outputs.id
  logic_app_resource_id  = dependency.logic_app.outputs.id
  logic_app_callback_url = dependency.logic_app.outputs.callback_url
  monthly_budget_usd     = include.env.locals.monthly_budget
}