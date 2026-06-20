# Found in: infra/terragrunt.hcl

remote_state {
  backend = "azurerm"
  config = {
    # Enterprise: Read from environment variables (No hardcoding!)
    resource_group_name  = get_env("TF_STATE_RG", "") 
    storage_account_name = get_env("TF_STATE_SA", "")
    container_name       = get_env("TF_STATE_CONTAINER", "tfstate")
    key                  = "${path_relative_to_include()}/terraform.tfstate"
    
    # Enterprise: Use Azure AD Authentication (No storage account keys)
    use_azuread_auth     = true
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_version = ">= 1.7.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 3.85" }
    azapi   = { source = "Azure/azapi", version = "~> 1.9" }
  }
}
provider "azurerm" {
  features {
    key_vault { purge_soft_delete_on_destroy = false }
    resource_group { prevent_deletion_if_contains_resources = true }
  }
  use_oidc = true
}
EOF
}

inputs = {
  default_tags = {
    ManagedBy = "terragrunt"
    Project   = "cost-visibility-dashboard"
    DataClass = "Confidential"
  }
}