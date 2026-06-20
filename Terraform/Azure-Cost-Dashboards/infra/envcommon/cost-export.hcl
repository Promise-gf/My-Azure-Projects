terraform { source = "${dirname(find_in_parent_folders())}//modules/cost-export" }
inputs = {
  export_recurrence = "Daily"
}