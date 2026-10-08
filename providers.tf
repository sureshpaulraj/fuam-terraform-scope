# Authentication is taken from the environment (Azure CLI login, OIDC, or
# ARM_*/FABRIC_* environment variables). Do not put secrets in .tf files.

provider "fabric" {
  tenant_id = var.tenant_id
}

provider "azuread" {
  tenant_id = var.tenant_id
}

# Only used when enable_key_vault = true. Still needs a subscription ID to initialize.
provider "azurerm" {
  features {}
  tenant_id       = var.tenant_id
  subscription_id = var.azure_subscription_id
}
