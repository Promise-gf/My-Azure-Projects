include "root" { path = find_in_parent_folders() }
include "env"  { path = "${dirname(find_in_parent_folders())}/env.hcl" expose = true }

terraform {
  source = "${dirname(find_in_parent_folders())}//modules/resource-group"
}

inputs = {
  name     = "rg-${include.env.locals.name_prefix}-${include.env.locals.env}"
  location = include.env.locals.location
}