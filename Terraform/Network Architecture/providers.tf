terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.70"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  # Leave this completely empty!
  # Terraform will merge the -backend-config="..." flags 
  # from your GitHub Actions YAML into this empty block at runtime.
  backend "azurerm" {}
}

# Only ONE provider block is allowed.
provider "azurerm" {
  features {}
  # Do NOT put use_oidc here. It is handled by env vars.
}

# Required for generating a unique storage account name
resource "random_id" "storage" {
  byte_length = 8
}

# Fetches details of the currently logged-in Azure user
data "azurerm_client_config" "current" {}