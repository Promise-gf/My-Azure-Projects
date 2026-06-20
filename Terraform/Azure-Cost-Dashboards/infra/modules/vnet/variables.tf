# modules/vnet/variables.tf

variable "name_prefix" {
  description = "Naming prefix for all resources e.g. corp-prod"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group to deploy into"
  type        = string
}

variable "address_space" {
  description = "VNet address space CIDR block e.g. 10.0.0.0/16"
  type        = string
}

variable "function_subnet_prefix" {
  description = "CIDR prefix for the Function App delegated subnet e.g. 10.0.1.0/24"
  type        = string
}

variable "pe_subnet_prefix" {
  description = "CIDR prefix for the Private Endpoint subnet e.g. 10.0.2.0/24"
  type        = string
}

variable "default_tags" {
  description = "Tags to apply to all resources in this module"
  type        = map(string)
  default     = {}
}