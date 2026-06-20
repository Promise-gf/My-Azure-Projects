variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "name_prefix" { type = string }
variable "environment" { type = string }

# UPDATED: No longer passing Logic App ID/Callback, passing Function URL
variable "self_heal_function_url" { 
  type        = string 
  description = "The HTTP trigger URL of the self_heal_trigger Python Function (includes the function key)."
}

variable "alert_emails" { 
  type        = list(string) 
  default     = [] 
  description = "List of email addresses to receive FinOps anomaly alerts."
}

variable "default_tags" {
  type    = map(string)
  default = {}
}