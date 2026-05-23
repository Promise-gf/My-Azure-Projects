variable "name"                { type = string }
variable "location"            { type = string }
variable "resource_group_name" { type = string }
variable "address_space"       { type = string }
variable "tags"                { type = map(string) }

variable "subnets" {
  type        = map(string)
  description = "Standard subnets that will have NSGs attached."
}

variable "nsg_ids" {
  type        = map(string)
  description = "Map of subnet names to their corresponding NSG IDs."
}

variable "deploy_vpn"      { type = bool }
variable "deploy_bastion"  { type = bool }
variable "deploy_firewall" { type = bool }
variable "gateway_cidr"    { type = string }
variable "bastion_cidr"    { type = string }
variable "firewall_cidr"   { type = string }

variable "service_endpoints" {
  description = "Map of subnet name to list of service endpoints."
  type        = map(list(string))
  default     = {}
}