variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "function_app_name" { type = string }
variable "storage_account_name" { type = string }
variable "storage_account_id" { type = string }
variable "key_vault_name" { type = string }
variable "key_vault_id" { type = string }
variable "app_insights_connection_string" { type = string }
variable "app_service_plan_sku" {
  type = string
  default = "Y1"
}
variable "environment" { type = string }
variable "subscription_id" { type = string }
variable "acr_login_server" { type = string }
variable "container_image_name" { type = string }
variable "container_image_tag" { type = string }
variable "app_settings" {
  type    = map(string)
  default = {}
}
variable "default_tags" {
  type    = map(string)
  default = {}
}
# Exceptional: Prod VNet Integration
variable "vnet_subnet_id" {
  type        = string
  default     = null
  description = "Required for Prod VNet Integration"
}
variable "dcr_endpoint" {
  type    = string
  default = ""
}
variable "dcr_immutable_id" {
  type    = string
  default = ""
}
variable "dcr_stream_name" {
  type    = string
  default = "Custom-CostEnrichmentLogs_CL"
}