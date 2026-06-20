include "root"      { path = find_in_parent_folders() }
include "envcommon" { path = "${dirname(find_in_parent_folders())}/_envcommon/logic-app.hcl" expose = true }
include "env"       { path = "${dirname(find_in_parent_folders())}/env.hcl" expose = true }
dependency "resource_group" { config_path = "../resource-group"; mock_outputs = { name = "mock-rg", location = "eastus" } }
inputs = {
  resource_group_name = dependency.resource_group.outputs.name
  location            = dependency.resource_group.outputs.location
  name_prefix         = include.env.locals.name_prefix
  environment         = include.env.locals.env
  subscription_id     = get_env("ARM_SUBSCRIPTION_ID")
}