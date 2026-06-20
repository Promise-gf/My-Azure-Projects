variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "grafana_name" { type = string }
variable "tenant_id" { type = string }
variable "log_analytics_workspace_id" { type = string }
variable "storage_account_id" { type = string }
variable "storage_account_name" { type = string }
variable "environment" { type = string }
variable "grafana_sku" {
  type    = string
  default = "Standard"
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