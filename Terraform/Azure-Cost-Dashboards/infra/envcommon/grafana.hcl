terraform { source = "${dirname(find_in_parent_folders())}//modules/managed-grafana" }
inputs = {
  grafana_sku = "Standard"
}