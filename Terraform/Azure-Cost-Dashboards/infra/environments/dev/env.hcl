locals {
  env            = "dev"
  name_prefix    = "cvd"
  location       = "cus"
  function_sku   = "Y1"
  monthly_budget = 500
  
  # Phase 11 Feature Flag: Container Apps Migration
  use_container_apps = false 
}