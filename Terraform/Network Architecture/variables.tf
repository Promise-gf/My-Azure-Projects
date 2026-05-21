# ==========================================
# INPUT VARIABLES
# ==========================================

variable "resource_group_name" {
  description = "The name of the existing Resource Group to deploy into."
  type        = string
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "centralus"
}

variable "prefix" {
  description = "Naming prefix for all resources (e.g., corp, projx)."
  type        = string
  default     = "corp"

  validation {
    condition     = length(var.prefix) >= 2 && length(var.prefix) <= 10
    error_message = "Prefix must be between 2 and 10 characters."
  }
}

variable "environment" {
  description = "Deployment environment: dev, test, prod."
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Environment must be dev, test, or prod."
  }
}

variable "vnet1_address_space" {
  description = "CIDR for the Hub VNet."
  type        = string
  default     = "10.10.0.0/16"
}

variable "vnet2_address_space" {
  description = "CIDR for the Spoke VNet."
  type        = string
  default     = "10.20.0.0/16"
}

variable "subnets" {
  description = "Map of subnet names to CIDR blocks."
  type = object({
    web                 = string
    app                 = string
    db                  = string
    pe                  = string
    secondary           = string
  })
}

variable "management_public_ip" {
  description = "CIDR allowed for SSH/RDP management."
  type        = string
  default     = "192.168.10.0/24"
}

variable "vpn_client_pool" {
  description = "IP pool assigned to VPN clients."
  type        = string
  default     = "192.168.10.0/24"
}

# ==========================================
# FEATURE TOGGLES
# ==========================================
variable "deploy_vpn" {
  type    = bool
  default = true
}
variable "deploy_bastion" {
  type    = bool
  default = true
}

variable "deploy_firewall" {
  type    = bool
  default = true
}

variable "deploy_log_analytics" {
  type    = bool
  default = true
}

variable "deploy_key_vault" {
  type    = bool
  default = true
}

variable "deploy_private_endpoints" {
  type    = bool
  default = true
}

variable "vpn_root_cert_data" {
  description = "Base64 encoded VPN root certificate."
  type        = string
  # sensitive = true ensures this is NEVER printed in your terminal during terraform plan/apply
  sensitive = true
  default   = ""
}

variable "vpn_root_cert_name" {
  type    = string
  default = "P2S-Root-Cert"
}

variable "tags" {
  description = "Extra tags to apply to all resources."
  type        = map(string)
  default     = {}
}

variable "gateway_cidr"  { type = string }
variable "bastion_cidr"  { type = string }
variable "firewall_cidr" { type = string }