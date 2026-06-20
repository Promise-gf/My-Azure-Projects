include "root" { path = find_in_parent_folders() }
include "env"  { path = "${dirname(find_in_parent_folders())}/env.hcl" expose = true }

dependency "resource_group" { 
  config_path = "../resource-group"
  mock_outputs = { name = "mock-rg", location = "eastus" }
}

dependency "monitoring" { 
  config_path = "../monitoring"
  mock_outputs = { log_analytics_workspace_id = "/sub/mock/la" }
}

dependency "function-app" { 
  config_path = "../function-app"
  mock_outputs = { principal_id = "00000000-0000-0000-0000-000000000000" }
}

terraform {
  source = "${dirname(find_in_parent_folders())}//modules/dcr"
}

inputs = {
  resource_group_name        = dependency.resource_group.outputs.name
  location                   = dependency.resource_group.outputs.location
  name_prefix                = include.env.locals.name_prefix
  environment                = include.env.locals.env
  log_analytics_workspace_id = dependency.monitoring.outputs.log_analytics_workspace_id
  function_principal_id      = dependency.function-app.outputs.principal_id
}