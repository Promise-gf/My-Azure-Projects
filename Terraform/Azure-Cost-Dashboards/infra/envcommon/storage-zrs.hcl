terraform { source = "${dirname(find_in_parent_folders())}//modules/storage-zrs" }
inputs = {
  account_replication_type = "ZRS"
  min_tls_version          = "TLS1_2"
}