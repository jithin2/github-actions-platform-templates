terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # Backend populated at init time via backend-config-file input.
  # In CI: terraform init -backend-config=backend.tfvars
  # backend.tfvars contains: resource_group_name, storage_account_name,
  # container_name, key — kept out of source control.
  backend "azurerm" {}
}

provider "azurerm" {
  features {}
}
