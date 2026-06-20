variable "enabled" {
  type        = bool
  default     = false
  description = "Feature flag for Phase 11 opt-in"
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "environment" {
  type = string
}

variable "storage_account_name" {
  type = string
}

variable "acr_login_server" {
  type = string
}

variable "vnet_subnet_id" {
  type    = string
  default = null
}

variable "default_tags" {
  type    = map(string)
  default = {}
}