variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "name_prefix" { type = string }
variable "environment" { type = string }
variable "log_analytics_workspace_id" { type = string }
variable "function_principal_id" { type = string }
variable "default_tags" {
  type    = map(string)
  default = {}
}