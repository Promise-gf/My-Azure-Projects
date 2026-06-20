terraform { source = "${dirname(find_in_parent_folders())}//modules/function-app-python" }
inputs = {
  os_type             = "linux"
  deployment_method   = "container"
  use_managed_identity = true
}