variable "name"                { type = string }
variable "location"            { type = string }
variable "resource_group_name" { type = string }
variable "tags"                { type = map(string) }

variable "tier_type" {
  type        = string
  description = "Defines which rules to generate (web, app, database, secondary)."
}

# These default to empty strings. If they are empty, they are ignored by the dynamic block.
variable "management_ip" {
  type = string
  default = ""
}
variable "vpn_pool"{ 
  type = string
 default = ""
  }
variable "web_cidr"{ 
  type = string
  default = ""
   }
variable "app_cidr" { 
type = string 
default = "" 
}
variable "spoke_cidr" { 
  type = string 
  default = "" 
  }
variable "hub_cidr" { 
  type = string
   default = "" 
   }