# FUAM on Power BI Premium (P SKU) — Terraform + Runbook

Infrastructure-as-Code for the **platform layer** of [FUAM (Fabric Unified Admin Monitoring)](https://github.com/microsoft/fabric-toolbox/tree/main/monitoring/fabric-unified-admin-monitoring), targeting an existing **Power BI Premium (P SKU)** capacity. It also works unchanged with a Fabric F SKU.

> ⚠️ **FUAM is not an official Microsoft service.** It is a community-driven solution accelerator with no Microsoft support SLA. Also evaluate the in-product monitoring announced at FabCon Barcelona 2026: Observability in Fabric (preview), Real-Time Hub Capacity Overview Events and capacity alert templates (GA). Confirm P-SKU support for each.

## What Terraform manages vs. what stays manual

| Step | Owner | File |
|---|---|---|
| FUAM service principal + rotating client secret (no API permissions) | Terraform | `identity.tf` |
| `sg-fuam-service-principals` and `sg-fuam-admins` security groups | Terraform | `identity.tf` |
| Tenant settings: Fabric items, XMLA, SP Fabric APIs, SP read-only admin APIs (opt-in) | Terraform | `tenant_settings.tf` |
| `FUAM` workspace on the existing P capacity + admin role | Terraform | `fabric.tf` |
| `FUAM Capacity Metrics` workspace rename + move to the P capacity (after import) | Terraform | `fabric.tf` |
| Upload of `Deploy_FUAM.ipynb` | Terraform | `fabric.tf` |
| Both FUAM cloud connections **with SP credentials** (no manual credential entry) | Terraform | `connections.tf` |
| Key Vault + SP secrets + RBAC (optional) | Terraform | `keyvault.tf` |
| P capacity itself (M365 licensing) | ❌ Existing | lookup only |
| P-capacity settings: XMLA Endpoint = Read, Fabric delegated override | ❌ Manual | Admin portal |
| Install the Capacity Metrics App (AppSource) | ❌ Manual | — |
| **Run** `Deploy_FUAM` (install + every update) | ❌ FUAM admin user | — |
| Pipeline parameters, initial load, semantic model refresh, daily schedule | ❌ FUAM admin user | — |

Why the last rows stay manual: FUAM's capacity-metrics notebooks query the Metrics App with **sempy as the notebook owner**, and pipelines run as the **user who last modified them**. Service-principal-only execution is on the FUAM roadmap (see `FUAM_Authorization.md`). If Terraform created or edited the pipeline or schedule, those notebooks would run as the Terraform identity and fail.

## Prerequisites

- Terraform >= 1.11 (write-only attributes), Azure CLI.
- Terraform identity (user or CI service principal/managed identity) with:
  - Entra: create applications and groups (for example `Application.ReadWrite.OwnedBy` + `Group.ReadWrite.All`, or Application Administrator + Groups Administrator).
  - Fabric: Fabric Administrator, plus permission to assign workspaces to the P capacity (capacity admin or contributor).
  - If using an SP for Terraform: it must be allowed by the *Service principals can use Fabric APIs* tenant setting, and its tenant-settings calls need Fabric admin API rights.
  - Azure (Key Vault): Contributor + User Access Administrator on the subscription or resource group.
- FUAM admin users hold the **Fabric Administrator** Entra role permanently (not just-in-time through PIM).
- Fabric workloads enabled on the P capacity (FUAM uses a lakehouse, notebooks and pipelines).

## Deployment runbook

### 1. Configure

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars   # edit values
az login --tenant <tenant-id>
terraform init
```

Use the commented `backend "azurerm"` in `versions.tf` for remote state. **State contains the SP secret.**

### 2. First apply (platform)

```powershell
terraform plan -out tfplan
terraform apply tfplan
```

Creates the SP, groups, `FUAM` workspace, connections with credentials, Key Vault, and uploads `Deploy_FUAM`.

### 3. Tenant settings (opt-in)

Set `manage_tenant_settings = true`, then run `terraform plan` and **review it with the Fabric admin team**.
- Resolution is by setting title. If a title differs in your tenant, the plan fails with instructions. Look up `settingName` with `GET https://api.fabric.microsoft.com/v1/admin/tenantsettings` and set `tenant_setting_name_overrides`.
- Existing configuration is preserved: org-wide settings stay org-wide, and existing groups, exclusions and delegations are kept. The FUAM group is appended.
- `delete_behaviour = "NoChange"`, so `terraform destroy` never switches settings off.

Alternatively, enable these manually in the Admin portal:
- *Users can create Fabric items* → `sg-fuam-admins`
- *Allow XMLA endpoints and Analyze in Excel…* → `sg-fuam-admins`
- *Service principals can use (call) Fabric public APIs* → `sg-fuam-service-principals`
- *Service principals can access read-only admin APIs* → `sg-fuam-service-principals`

### 4. P-capacity settings (manual, Admin portal → Capacity settings → your P capacity)

- Power BI workloads → **XMLA Endpoint = Read** (or Read Write).
- Delegated tenant settings → confirm *Users can create Fabric items* is not disabled at the capacity level.

### 5. Capacity Metrics App (manual)

1. Install a **FUAM-compatible** version of *Microsoft Fabric Capacity Metrics* from AppSource. Check the FUAM docs for supported versions.
2. Configure it for the P capacity.
3. Copy the new workspace's ID into `capacity_metrics_workspace_id`, then:

```powershell
terraform apply
```

Terraform imports the workspace, renames it to `FUAM Capacity Metrics`, moves it from Pro to the P capacity, and grants `sg-fuam-admins` Contributor.

### 6. Install FUAM (FUAM admin user)

1. Open the `FUAM` workspace → `Deploy_FUAM` → **Run All**.
2. The notebook finds the Terraform-created connections by name and reuses them, so there is **no manual credential entry**.

### 7. Configure and run the pipeline (FUAM admin user)

Open `Load_FUAM_Data_E2E` and set the parameters from `terraform output load_fuam_data_e2e_pipeline_parameters`:
- `metric_workspace`, `metric_dataset`
- The `optional_keyvault_*` names (makes the Scanner API run as the SP)
- Initial load: `metric_days_in_scope = 14`, `activity_days_in_scope = 28`
- Start `om_top_n_semantic_models_per_capacity` small

Run the pipeline. Then refresh `FUAM_Core_SM` and `FUAM_Item_SM`.

### 8. Daily schedule (FUAM admin user)

Change the parameters to the incremental values (`metric_days_in_scope = 2`, `activity_days_in_scope = 2`), save, and schedule daily **off-peak**. FUAM shares the production P capacity, so watch FUAM's CU usage in the Metrics App for the first two weeks.

## Day-2 operations

| Task | How |
|---|---|
| FUAM update | FUAM admin re-runs `Deploy_FUAM` (items are overwritten by name). No Terraform change. |
| Secret rotation | Automatic after `sp_secret_rotation_days` on the next `terraform apply`. Bump `sp_secret_version` to push the new secret to both connections. Key Vault updates automatically. |
| New FUAM admin | Add the UPN to `fuam_admin_user_upns` and apply. |
| Move to an F SKU | Point `premium_capacity_name` at the F capacity (or add `azurerm_fabric_capacity`) and apply. Workspaces are reassigned. |
| Remove FUAM | `terraform destroy` removes workspaces, connections, SP, groups and Key Vault (purge protection keeps the vault soft-deleted). Tenant settings are left unchanged. |

## Notes and limitations

- Validated with `terraform validate` using Terraform 1.16.5: fabric 1.14.0, azuread 3.10.0, azurerm 4.81.0, time 0.14.2. **Run a full `plan`/`apply` in a non-production tenant or on a Fabric trial capacity first.**
- `notebooks/Deploy_FUAM.ipynb` is a copy of the upstream file (MIT license). To pick up a changed deploy notebook, replace the file and run `terraform apply -replace=fabric_notebook.deploy_fuam`.
- The Fabric connection test runs when the connections are created (`WebForPipeline` connections don't support skipping it). Tenant settings must allow the SP before the connections are created; if the first apply fails here, wait a few minutes for settings to propagate and re-apply.
- Private Link tenants need extra manual steps per the FUAM docs.

## Deployment considerations

- **Key Vault and Azure Policy:** some organizations enforce a policy (for example "Disable public network access on Key Vaults", Modify effect) that switches off public network access after the vault is created. Terraform then gets `403 ForbiddenByConnection` when writing secrets. In that case, either:
  - set `enable_key_vault = false` (FUAM falls back to the notebook owner's identity for the Scanner API), or
  - deploy the vault with a private endpoint, run Terraform from a network that can reach it, and give FUAM a Fabric managed private endpoint to the vault.
- **Existing FUAM installs:** if a `FUAM` workspace or the default `fuam … admin` connections already exist, the apply fails with `WorkspaceNameAlreadyExists` / `DuplicateConnectionName`. Either deploy side by side by setting `fuam_workspace_name`, `pbi_connection_name` and `fabric_connection_name` (the uploaded notebook is patched to match), or `terraform import` the existing items. Importing re-points the connection credentials to the Terraform-managed service principal.
- **Plan files are sensitive:** `terraform plan -out tfplan` writes a binary plan that can contain secret values. It is git-ignored; never commit it, and delete it after applying.
