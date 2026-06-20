variable "name_prefix" {
  description = "Short name prefix used in all resource names (e.g. cvd)"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev or prod)"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Environment must be dev or prod."
  }
}

variable "location" {
  description = "Azure region to deploy resources into (e.g. eastus)"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group to deploy into"
  type        = string
}

variable "default_tags" {
  description = "Tags applied to all resources in this module"
  type        = map(string)
  default     = {}
}