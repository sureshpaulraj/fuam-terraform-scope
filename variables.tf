# ---------------------------------------------------------------------------
# Tenant / Azure
# ---------------------------------------------------------------------------
variable "tenant_id" {
  description = "Entra ID tenant ID."
  type        = string
}

variable "azure_subscription_id" {
  description = "Azure subscription for the optional Key Vault. Required by the azurerm provider even if enable_key_vault = false."
  type        = string
}

# ---------------------------------------------------------------------------
# Power BI Premium capacity (existing P SKU - not managed by Terraform)
# ---------------------------------------------------------------------------
variable "premium_capacity_name" {
  description = "Display name of the existing Power BI Premium (P SKU) capacity that will host FUAM and the FUAM Capacity Metrics workspace."
  type        = string
}

# ---------------------------------------------------------------------------
# People
# ---------------------------------------------------------------------------
variable "fuam_admin_user_upns" {
  description = "UPNs of Fabric Administrators who run Deploy_FUAM and own the FUAM notebooks/pipelines. Must hold the Fabric Administrator Entra role permanently."
  type        = list(string)

  validation {
    condition     = length(var.fuam_admin_user_upns) > 0
    error_message = "At least one FUAM admin user is required (FUAM's notebooks currently run as a user)."
  }
}

variable "add_terraform_identity_to_admin_group" {
  description = "Add the identity running Terraform to the FUAM admins group so it can create Fabric items (the Deploy_FUAM notebook) in the FUAM workspace."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Naming
# ---------------------------------------------------------------------------
variable "fuam_workspace_name" {
  type    = string
  default = "FUAM"
}

variable "capacity_metrics_workspace_name" {
  description = "Target name for the Capacity Metrics App workspace (the app itself is installed manually from AppSource)."
  type        = string
  default     = "FUAM Capacity Metrics"
}

variable "capacity_metrics_workspace_id" {
  description = "ID of the workspace created by the manual Capacity Metrics App install. Leave empty on the first apply; set it afterwards to import and manage the workspace (rename + P capacity assignment)."
  type        = string
  default     = ""
}

variable "service_principal_name" {
  type    = string
  default = "sp-fuam-admin-api"
}

variable "sp_group_name" {
  description = "Security group that contains the FUAM service principal and is allowed in the SP admin-API tenant settings."
  type        = string
  default     = "sg-fuam-service-principals"
}

variable "admin_group_name" {
  description = "Security group that contains the FUAM admin users. Used for workspace roles, connection roles, and user-scoped tenant settings."
  type        = string
  default     = "sg-fuam-admins"
}

variable "pbi_connection_name" {
  description = "Must match pbi_connection_name in Deploy_FUAM.ipynb (the uploaded notebook is patched to this value)."
  type        = string
  default     = "fuam pbi-service-api admin"
}

variable "fabric_connection_name" {
  description = "Must match fabric_connection_name in Deploy_FUAM.ipynb (the uploaded notebook is patched to this value)."
  type        = string
  default     = "fuam fabric-service-api admin"
}

# ---------------------------------------------------------------------------
# Service principal secret
# ---------------------------------------------------------------------------
variable "sp_secret_rotation_days" {
  description = "Client secret lifetime. A new secret is generated, and the connections and Key Vault are updated, when this elapses and you re-apply."
  type        = number
  default     = 180
}

variable "sp_secret_version" {
  description = "Increase this whenever the SP secret changes so the write-only connection credentials are pushed again."
  type        = number
  default     = 1
}

# ---------------------------------------------------------------------------
# Tenant settings
# ---------------------------------------------------------------------------
variable "manage_tenant_settings" {
  description = "Let Terraform manage the four tenant settings FUAM needs. Review the plan carefully - these are tenant-wide."
  type        = bool
  default     = false
}

variable "tenant_setting_name_overrides" {
  description = "Optional map of logical key => API setting_name, if title lookup fails in your tenant. Keys: fabric_items, xmla, sp_fabric_apis, sp_readonly_admin_apis."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Optional Azure Key Vault (lets the Scanner API notebook run as the SP)
# ---------------------------------------------------------------------------
variable "enable_key_vault" {
  type    = bool
  default = true
}

variable "key_vault_name" {
  description = "Globally unique Key Vault name (3-24 chars)."
  type        = string
  default     = "kv-fuam-change-me"
}

variable "resource_group_name" {
  type    = string
  default = "rg-fuam"
}

variable "location" {
  type    = string
  default = "centralus"
}

variable "tags" {
  type = map(string)
  default = {
    workload = "FUAM"
    owner    = "fabric-admins"
  }
}
