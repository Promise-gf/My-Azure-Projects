variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "storage_account_name" { type = string }
variable "account_replication_type" {
  type    = string
  default = "ZRS"
}
variable "min_tls_version" {
  type    = string
  default = "TLS1_2"
}

variable "default_tags" {
  type    = map(string)
  default = {}
}

# Exceptional: Prod Private Endpoint
variable "private_endpoint_subnet_id" {
  type    = string
  default = null
}