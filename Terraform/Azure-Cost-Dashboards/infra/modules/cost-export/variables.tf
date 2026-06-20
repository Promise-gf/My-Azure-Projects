variable "billing_scope_id" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "environment" {
  type = string
}

variable "storage_account_id" {
  type = string
}

variable "storage_container_name" {
  type    = string
  default = "cost-exports"
}

variable "export_recurrence" {
  type    = string
  default = "Daily"
}

variable "default_tags" {
  type    = map(string)
  default = {}
}