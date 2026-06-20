include "root"      { path = find_in_parent_folders() }
include "envcommon" { path = "${dirname(find_in_parent_folders())}/_envcommon/cost-export.hcl" expose = true }
include "env"       { path = "${dirname(find_in_parent_folders())}/env.hcl" expose = true }

dependency "resource_group" { config_path = "../resource-group"; mock_outputs = { id = "/sub/mock/rg" } }
dependency "storage"        { config_path = "../storage-zrs";    mock_outputs = { id = "/sub/mock/st" } }

inputs = {
  billing_scope_id       = "/subscriptions/${get_env("ARM_SUBSCRIPTION_ID")}"
  name_prefix            = include.env.locals.name_prefix
  environment            = include.env.locals.env
  storage_account_id     = dependency.storage.outputs.id
  storage_container_name = "cost-exports"
}