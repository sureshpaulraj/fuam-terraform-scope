# ---------------------------------------------------------------------------
# Existing Power BI Premium capacity (P SKU). Purchased via M365 licensing,
# so it is looked up, not created. When you move to an F SKU, replace this
# with azurerm_fabric_capacity (or just point premium_capacity_name at the F capacity).
# ---------------------------------------------------------------------------
data "fabric_capacity" "premium" {
  display_name = var.premium_capacity_name

  lifecycle {
    postcondition {
      condition     = self.state == "Active"
      error_message = "Capacity '${var.premium_capacity_name}' is not Active."
    }
  }
}

# ---------------------------------------------------------------------------
# FUAM workspace
# ---------------------------------------------------------------------------
resource "fabric_workspace" "fuam" {
  display_name = var.fuam_workspace_name
  description  = "FUAM - Fabric Unified Admin Monitoring (community solution accelerator, not an official Microsoft service). Items are deployed/updated by the Deploy_FUAM notebook, not Terraform."
  capacity_id  = data.fabric_capacity.premium.id
}

resource "fabric_workspace_role_assignment" "fuam_admins" {
  workspace_id = fabric_workspace.fuam.id
  principal = {
    id   = azuread_group.fuam_admins.object_id
    type = "Group"
  }
  role = "Admin"
}

# ---------------------------------------------------------------------------
# FUAM Capacity Metrics workspace
# The Capacity Metrics App is installed MANUALLY from AppSource (no API).
# After install, set capacity_metrics_workspace_id and re-apply: Terraform imports
# the workspace, renames it, and moves it from Pro to the P capacity.
# ---------------------------------------------------------------------------
locals {
  metrics_ws = var.capacity_metrics_workspace_id == "" ? toset([]) : toset(["this"])
}

import {
  for_each = local.metrics_ws
  to       = fabric_workspace.capacity_metrics[each.key]
  id       = var.capacity_metrics_workspace_id
}

resource "fabric_workspace" "capacity_metrics" {
  for_each = local.metrics_ws

  display_name = var.capacity_metrics_workspace_name
  description  = "Dedicated Microsoft Fabric Capacity Metrics App instance for FUAM. Keep on a FUAM-compatible app version."
  capacity_id  = data.fabric_capacity.premium.id
}

# FUAM's capacity-metrics notebooks run as the pipeline's last modifier, who needs Contributor here.
resource "fabric_workspace_role_assignment" "capacity_metrics_fuam_admins" {
  for_each = local.metrics_ws

  workspace_id = fabric_workspace.capacity_metrics[each.key].id
  principal = {
    id   = azuread_group.fuam_admins.object_id
    type = "Group"
  }
  role = "Contributor"
}

# ---------------------------------------------------------------------------
# Deploy_FUAM notebook - uploaded only. It must be RUN by a FUAM admin user
# (initial install and every FUAM update). Terraform never manages the items it creates.
# ---------------------------------------------------------------------------
resource "fabric_notebook" "deploy_fuam" {
  display_name = "Deploy_FUAM"
  description  = "Run All as a Fabric Administrator to install/update FUAM. Source: github.com/microsoft/fabric-toolbox (MIT)."
  workspace_id = fabric_workspace.fuam.id
  format       = "ipynb"

  # Upload once; FUAM self-updates by re-running this notebook. Refresh the file in ./notebooks
  # and taint this resource only if the deploy notebook itself changes upstream.
  definition_update_enabled = false

  definition = {
    "notebook-content.ipynb" = {
      source = "${path.module}/notebooks/Deploy_FUAM.ipynb"
      # The notebook contains literal {{...}} strings, so Go templating must not be used.
      processing_mode = "Parameters"
      parameters = [
        {
          type  = "TextReplace"
          find  = "pbi_connection_name = 'fuam pbi-service-api admin'"
          value = "pbi_connection_name = '${var.pbi_connection_name}'"
        },
        {
          type  = "TextReplace"
          find  = "fabric_connection_name = 'fuam fabric-service-api admin'"
          value = "fabric_connection_name = '${var.fabric_connection_name}'"
        }
      ]
    }
  }

  depends_on = [
    fabric_workspace_role_assignment.fuam_admins,
    fabric_tenant_setting.fuam,
  ]
}
