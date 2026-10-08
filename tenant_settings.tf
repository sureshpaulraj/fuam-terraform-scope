# ---------------------------------------------------------------------------
# Fabric tenant settings required by FUAM
#
#   User-scoped (FUAM admins group):
#     - Users can create Fabric items             (needed on a P SKU - FUAM is lakehouse/notebooks/pipelines)
#     - Allow XMLA endpoints and Analyze in Excel (capacity-metrics notebooks query the Metrics App via XMLA)
#   SP-scoped (FUAM SP group):
#     - Service principals can use / call Fabric public APIs
#     - Service principals can access read-only admin APIs
#
# SAFETY: the current tenant configuration is read first and preserved:
#   - settings already enabled for the ENTIRE organization stay org-wide (no group restriction is added)
#   - existing enabled/excluded security groups and delegation flags are kept; FUAM's group is appended
#   - delete_behaviour = "NoChange" -> terraform destroy never switches a tenant setting off
# Off by default. Set manage_tenant_settings = true after reviewing the plan with the Fabric admin team.
# ---------------------------------------------------------------------------

locals {
  required_tenant_settings = {
    fabric_items = {
      titles   = ["Users can create Fabric items"]
      group_id = azuread_group.fuam_admins.object_id
    }
    xmla = {
      titles = [
        "Allow XMLA endpoints and Analyze in Excel with on-premises semantic models",
        "Allow XMLA endpoints and Analyze in Excel with on-premises datasets",
      ]
      group_id = azuread_group.fuam_admins.object_id
    }
    sp_fabric_apis = {
      titles = [
        "Service principals can use Fabric APIs",
        "Service principals can call Fabric public APIs",
      ]
      group_id = azuread_group.fuam_sp.object_id
    }
    sp_readonly_admin_apis = {
      titles   = ["Service principals can access read-only admin APIs"]
      group_id = azuread_group.fuam_sp.object_id
    }
  }

  all_tenant_settings = var.manage_tenant_settings ? tolist(data.fabric_tenant_settings.all[0].values) : []

  tenant_setting_matches = {
    for k, v in local.required_tenant_settings : k => (
      contains(keys(var.tenant_setting_name_overrides), k)
      ? [for s in local.all_tenant_settings : s if s.setting_name == var.tenant_setting_name_overrides[k]]
      : [for s in local.all_tenant_settings : s if contains([for t in v.titles : lower(t)], lower(trimspace(s.title)))]
    )
  }

  current_tenant_settings = {
    for k, m in local.tenant_setting_matches : k => length(m) == 1 ? m[0] : null
  }

  current_enabled_group_ids = {
    for k, s in local.current_tenant_settings : k => (
      s == null ? [] : s.enabled_security_groups == null ? [] : [for g in s.enabled_security_groups : g.graph_id]
    )
  }

  current_excluded_group_ids = {
    for k, s in local.current_tenant_settings : k => (
      s == null ? [] : s.excluded_security_groups == null ? [] : [for g in s.excluded_security_groups : g.graph_id]
    )
  }

  # Already enabled for the whole organization -> leave org-wide.
  tenant_setting_is_org_wide = {
    for k, s in local.current_tenant_settings : k => (
      s == null ? false : (s.enabled == true && length(local.current_enabled_group_ids[k]) == 0)
    )
  }
}

data "fabric_tenant_settings" "all" {
  count = var.manage_tenant_settings ? 1 : 0
}

resource "fabric_tenant_setting" "fuam" {
  for_each = var.manage_tenant_settings ? local.required_tenant_settings : {}

  setting_name = local.current_tenant_settings[each.key] == null ? "UNRESOLVED-${each.key}" : local.current_tenant_settings[each.key].setting_name
  enabled      = true

  # Keep the setting org-wide if it already is; otherwise union existing groups with the FUAM group.
  enabled_security_groups = local.tenant_setting_is_org_wide[each.key] ? null : [
    for id in toset(concat(local.current_enabled_group_ids[each.key], [each.value.group_id])) : { graph_id = id }
  ]

  excluded_security_groups = length(local.current_excluded_group_ids[each.key]) == 0 ? null : [
    for id in toset(local.current_excluded_group_ids[each.key]) : { graph_id = id }
  ]

  delegate_to_capacity  = try(local.current_tenant_settings[each.key].delegate_to_capacity, null)
  delegate_to_domain    = try(local.current_tenant_settings[each.key].delegate_to_domain, null)
  delegate_to_workspace = try(local.current_tenant_settings[each.key].delegate_to_workspace, null)

  delete_behaviour = "NoChange"

  lifecycle {
    precondition {
      condition     = local.current_tenant_settings[each.key] != null
      error_message = "Could not uniquely resolve tenant setting '${each.key}' (titles: ${join(" | ", each.value.titles)}). Run GET https://api.fabric.microsoft.com/v1/admin/tenantsettings, find its settingName, and set tenant_setting_name_overrides[\"${each.key}\"]."
    }
  }
}
