terraform {
  # >= 1.11 is required for write-only arguments (client_secret_wo on fabric_connection).
  required_version = ">= 1.11, < 2.0"

  required_providers {
    fabric = {
      source  = "microsoft/fabric"
      version = "~> 1.14"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }

  # Recommended: remote state with encryption at rest and restricted access.
  # State contains the FUAM service principal secret.
  # backend "azurerm" {
  #   resource_group_name  = "rg-tfstate"
  #   storage_account_name = "sttfstatecontoso"
  #   container_name       = "tfstate"
  #   key                  = "fuam.tfstate"
  #   use_azuread_auth     = true
  # }
}
