locals {
  env            = "prod"
  name_prefix    = "cvd"
  location       = "centralus"
  function_sku   = "EP2"
  monthly_budget = 10000
  
  # Phase 11 Feature Flag: Turn this to 'true' when ready to migrate Prod
  use_container_apps = true
}