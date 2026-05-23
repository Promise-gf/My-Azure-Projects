variable "name"                { type = string }
variable "public_ip_name"      { type = string }
variable "location"            { type = string }
variable "resource_group_name" { type = string }
variable "subnet_id"           { type = string }
variable "tags"                { type = map(string) }
variable "vpn_client_pool"     { type = string }
variable "vpn_root_cert_name"  { type = string }
variable "vpn_root_cert_data" {
  type      = string
  sensitive = true
  default   = ""
}