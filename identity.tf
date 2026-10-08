# ---------------------------------------------------------------------------
# FUAM service principal + security groups (Entra ID)
# FUAM requires an SP with a client secret and NO API permissions.
# ---------------------------------------------------------------------------
data "azuread_client_config" "current" {}

data "azuread_user" "fuam_admins" {
  for_each            = toset(var.fuam_admin_user_upns)
  user_principal_name = each.value
}

resource "azuread_application" "fuam" {
  display_name = var.service_principal_name
  owners       = [data.azuread_client_config.current.object_id]
  notes        = "FUAM (Fabric Unified Admin Monitoring) - used by FUAM cloud connections and optional Key Vault. Do not add Power BI API permissions."
}

resource "azuread_service_principal" "fuam" {
  client_id = azuread_application.fuam.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

resource "time_rotating" "fuam_secret" {
  rotation_days = var.sp_secret_rotation_days
}

resource "azuread_application_password" "fuam" {
  application_id = azuread_application.fuam.id
  display_name   = "fuam-connections"
  end_date       = time_rotating.fuam_secret.rotation_rfc3339

  rotate_when_changed = {
    rotation = time_rotating.fuam_secret.id
  }
}

# Group for the SP, enabled in the two SP admin-API tenant settings.
resource "azuread_group" "fuam_sp" {
  display_name     = var.sp_group_name
  description      = "FUAM service principals - enabled for 'Service principals can use Fabric APIs' and 'Service principals can access read-only admin APIs'."
  security_enabled = true
  owners           = [data.azuread_client_config.current.object_id]
  members          = [azuread_service_principal.fuam.object_id]
}

# Group for FUAM admin users (and optionally the Terraform identity).
resource "azuread_group" "fuam_admins" {
  display_name     = var.admin_group_name
  description      = "FUAM admins - Fabric Administrators who deploy/update FUAM. Enabled for 'Users can create Fabric items' and XMLA endpoints."
  security_enabled = true
  owners           = [data.azuread_client_config.current.object_id]
  members = toset(concat(
    [for u in data.azuread_user.fuam_admins : u.object_id],
    var.add_terraform_identity_to_admin_group ? [data.azuread_client_config.current.object_id] : []
  ))
}
