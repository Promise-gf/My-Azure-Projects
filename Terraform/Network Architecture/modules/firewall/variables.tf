variable "name"                { type = string }
variable "public_ip_name"      { type = string }
variable "location"            { type = string }
variable "resource_group_name" { type = string }
variable "subnet_id"           { type = string }
variable "log_analytics_id"    { type = string }
variable "tags"                { type = map(string) }