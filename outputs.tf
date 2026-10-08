output "capacity" {
  description = "Capacity hosting FUAM. Expect a P SKU today."
  value = {
    id     = data.fabric_capacity.premium.id
    sku    = data.fabric_capacity.premium.sku
    region = data.fabric_capacity.premium.region
  }
}

output "fuam_workspace_id" {
  value = fabric_workspace.fuam.id
}

output "capacity_metrics_workspace_id" {
  value = try(fabric_workspace.capacity_metrics["this"].id, "NOT YET IMPORTED - install the Capacity Metrics App, then set capacity_metrics_workspace_id")
}

output "deploy_notebook_id" {
  value = fabric_notebook.deploy_fuam.id
}

output "fuam_connections" {
  value = { for k, c in fabric_connection.fuam : k => { id = c.id, name = c.display_name } }
}

output "service_principal" {
  value = {
    client_id      = azuread_application.fuam.client_id
    object_id      = azuread_service_principal.fuam.object_id
    secret_expires = azuread_application_password.fuam.end_date
  }
}

output "groups" {
  value = {
    fuam_admins = azuread_group.fuam_admins.object_id
    fuam_sp     = azuread_group.fuam_sp.object_id
  }
}

output "resolved_tenant_settings" {
  description = "Tenant setting API names Terraform resolved (only when manage_tenant_settings = true)."
  value       = { for k, s in local.current_tenant_settings : k => try(s.setting_name, null) }
}

output "load_fuam_data_e2e_pipeline_parameters" {
  description = "Values to enter in the Load_FUAM_Data_E2E pipeline (manual step)."
  value = {
    metric_workspace                          = var.capacity_metrics_workspace_name
    metric_dataset                            = "Fabric Capacity Metrics"
    optional_keyvault_name                    = var.enable_key_vault ? var.key_vault_name : ""
    optional_keyvault_sp_tenantId_secret_name = var.enable_key_vault ? "fuam-sp-tenant-id" : ""
    optional_keyvault_sp_clientId_secret_name = var.enable_key_vault ? "fuam-sp-client-id" : ""
    optional_keyvault_sp_secret_secret_name   = var.enable_key_vault ? "fuam-sp-client-secret" : ""
  }
}
