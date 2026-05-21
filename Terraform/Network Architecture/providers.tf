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

  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "tfstate50e5ccc5"
    container_name       = "tfstate"
    key                  = "network.terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
}

resource "random_id" "storage" {
  byte_length = 8
}

data "azurerm_client_config" "current" {}