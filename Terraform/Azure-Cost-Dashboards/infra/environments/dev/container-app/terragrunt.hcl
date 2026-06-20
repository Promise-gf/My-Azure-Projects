include "root" { path = find_in_parent_folders() }
include "env"  { path = "${dirname(find_in_parent_folders())}/env.hcl" expose = true }

dependency "resource_group" { config_path = "../resource-group"; mock_outputs = { name = "mock-rg", location = "eastus", id = "/sub/mock" } }
dependency "storage"        { config_path = "../storage-zrs";    mock_outputs = { id = "/sub/mock/st", name = "mockst" } }
# dependency "vnet"         { config_path = "../vnet"; mock_outputs = { function_subnet_id = "/sub/mock/vnet/snet" } }

terraform {
  source = "${dirname(find_in_parent_folders())}//modules/container-app"
}

inputs = {
  enabled              = include.env.locals.use_container_apps
  resource_group_name  = dependency.resource_group.outputs.name
  location             = dependency.resource_group.outputs.location
  name_prefix          = include.env.locals.name_prefix
  environment          = include.env.locals.env
  storage_account_name = dependency.storage.outputs.name
  acr_login_server     = "acr${include.env.locals.name_prefix}${include.env.locals.env}.azurecr.io"
  
  # Dev doesn't have a VNet, so we pass null
  vnet_subnet_id       = null 
}