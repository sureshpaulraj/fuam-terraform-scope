# ---------------------------------------------------------------------------
# FUAM cloud connections - pre-created WITH service principal credentials.
# Deploy_FUAM.ipynb uses create-or-get by name, so it reuses these instead of
# creating credential-less ones. This removes the manual "add credentials" step.
# Definitions mirror the notebook: WebForPipeline / WebForPipeline.Contents.
# ---------------------------------------------------------------------------
locals {
  fuam_connections = {
    pbi = {
      name     = var.pbi_connection_name
      base_url = "https://api.powerbi.com/v1.0/myorg/admin"
      audience = "https://analysis.windows.net/powerbi/api"
    }
    fabric = {
      name     = var.fabric_connection_name
      base_url = "https://api.fabric.microsoft.com/v1/admin"
      audience = "https://api.fabric.microsoft.com"
    }
  }
}

resource "fabric_connection" "fuam" {
  for_each = local.fuam_connections

  display_name      = each.value.name
  connectivity_type = "ShareableCloud"
  privacy_level     = "Organizational"

  connection_details = {
    type            = "WebForPipeline"
    creation_method = "WebForPipeline.Contents"
    parameters = [
      { name = "baseUrl", value = each.value.base_url },
      { name = "audience", value = each.value.audience },
    ]
  }

  credential_details = {
    credential_type       = "ServicePrincipal"
    connection_encryption = "NotEncrypted"
    single_sign_on_type   = "None"

    service_principal_credentials = {
      tenant_id                = var.tenant_id
      client_id                = azuread_application.fuam.client_id
      client_secret_wo         = azuread_application_password.fuam.value
      client_secret_wo_version = var.sp_secret_version
    }
  }

  # The connection test runs as the SP, so its group must already be allowed in the tenant settings.
  depends_on = [azuread_group.fuam_sp, fabric_tenant_setting.fuam]
}

# FUAM admins must be able to see/use the connections (the notebook resolves them by name,
# and pipelines run under the admin user's context).
resource "fabric_connection_role_assignment" "fuam_admins" {
  for_each = fabric_connection.fuam

  connection_id = each.value.id
  principal = {
    id   = azuread_group.fuam_admins.object_id
    type = "Group"
  }
  role = "Owner"
}
