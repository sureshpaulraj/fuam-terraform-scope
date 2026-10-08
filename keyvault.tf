# ---------------------------------------------------------------------------
# Optional Azure Key Vault
# With these secrets set in the Load_FUAM_Data_E2E pipeline parameters
# (optional_keyvault_*), the Scanner API notebook runs as the SP instead of the
# notebook owner. The capacity-metrics notebooks STILL run as the user (sempy/XMLA).
# ---------------------------------------------------------------------------
data "azurerm_client_config" "current" {
  count = var.enable_key_vault ? 1 : 0
}

resource "azurerm_resource_group" "fuam" {
  count    = var.enable_key_vault ? 1 : 0
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_key_vault" "fuam" {
  count = var.enable_key_vault ? 1 : 0

  name                       = var.key_vault_name
  location                   = azurerm_resource_group.fuam[0].location
  resource_group_name        = azurerm_resource_group.fuam[0].name
  tenant_id                  = var.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = true
  soft_delete_retention_days = 90
  tags                       = var.tags
}

# Lets the Terraform identity write the secrets.
resource "azurerm_role_assignment" "kv_terraform_secrets_officer" {
  count                = var.enable_key_vault ? 1 : 0
  scope                = azurerm_key_vault.fuam[0].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current[0].object_id
}

# FUAM notebooks read the vault as the notebook owner (a FUAM admin user).
resource "azurerm_role_assignment" "kv_fuam_admins_secrets_user" {
  count                = var.enable_key_vault ? 1 : 0
  scope                = azurerm_key_vault.fuam[0].id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azuread_group.fuam_admins.object_id
  principal_type       = "Group"
}

locals {
  kv_secrets = {
    "fuam-sp-tenant-id"     = var.tenant_id
    "fuam-sp-client-id"     = azuread_application.fuam.client_id
    "fuam-sp-client-secret" = azuread_application_password.fuam.value
  }
}

resource "azurerm_key_vault_secret" "fuam" {
  for_each = var.enable_key_vault ? nonsensitive(toset(keys(local.kv_secrets))) : toset([])

  name            = each.key
  value           = local.kv_secrets[each.key]
  key_vault_id    = azurerm_key_vault.fuam[0].id
  content_type    = "FUAM service principal"
  expiration_date = each.key == "fuam-sp-client-secret" ? time_rotating.fuam_secret.rotation_rfc3339 : null

  depends_on = [azurerm_role_assignment.kv_terraform_secrets_officer]
}
