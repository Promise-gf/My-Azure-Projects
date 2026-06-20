include "root" { path = find_in_parent_folders() }
include "env"  { path = "${dirname(find_in_parent_folders())}/env.hcl" expose = true }
dependency "resource_group" { config_path = "../resource-group"; mock_outputs = { name = "mock-rg", location = "eastus" } }
terraform { source = "${dirname(find_in_parent_folders())}//modules/key-vault" }
inputs = {
  resource_group_name = dependency.resource_group.outputs.name
  location            = dependency.resource_group.outputs.location
  key_vault_name      = "kv-${include.env.locals.name_prefix}-${include.env.locals.env}"
  tenant_id           = get_env("ARM_TENANT_ID")
}