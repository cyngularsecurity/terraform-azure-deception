# terraform-azure-deception

Terraform module that plants **inert Azure decoy (honeytoken) resources** into a client subscription — the Azure counterpart of [`terraform-aws-deception`](https://github.com/cyngularsecurity/terraform-aws-deception).

## Design

- **Freely RBAC-reachable, internet-read-blocked** — any authenticated interaction is a high-signal detection event.
- **Inert by zero role-assignments** — the module never creates `azurerm_role_assignment` or Graph directory role assignments for any decoy principal.
- **Lured by name, not capability** — intriguing-but-generic names and believable operational tags; nothing inside the resources is actionable.
- **No Cyngular reference anywhere in the tenant** — cover protection enforced by variable validation.
- **Attribution = created resource IDs (outputs) + caller-supplied tracking tag.**

## Resource kinds (v1)

| Kind | Azure resource(s) | Scope |
|---|---|---|
| Service Principal | `azuread_application` + `azuread_service_principal` + optional `azuread_application_password` + optional `azuread_conditional_access_policy` | Tenant |
| Managed Identity | `azurerm_user_assigned_identity` | Subscription / RG |
| Storage Account / Blob | `azurerm_storage_account` + container + decoy blobs | Subscription / RG, fans out over `var.locations` |
| Key Vault Secret | `azurerm_key_vault` + `azurerm_key_vault_secret` | Subscription / RG, fans out over `var.locations` |

## Required permissions

The Terraform apply principal needs:

**Subscription / resource-group scope**

| Permission | Required for |
|---|---|
| Contributor on the resource group | Storage Account, Key Vault, Managed Identity creation |
| Storage Blob Data Contributor on each storage account | Uploading decoy blobs via data plane (RBAC auth — see note below) |

**Tenant scope (Azure AD)**

| Permission | Required for |
|---|---|
| Application Administrator _or_ Cloud Application Administrator | App Registrations, Service Principals, client secrets |
| `Policy.ReadWrite.ConditionalAccess` (Graph) | Only when `service_principal.conditional_access_block = true` |

> **Storage data-plane auth note:** The module sets `shared_access_key_enabled = false` on every storage account so all data-plane touches are audit-logged via Azure RBAC. The `azurerm` provider must authenticate via Azure AD (not a storage key) to upload the decoy blobs. Ensure the provider is configured with a principal that holds **Storage Blob Data Contributor** on the account, or that `storage_use_azuread = true` is set in the provider block.

## Zero-role-assignment guarantee

The module does **not** create any of the following for decoy principals:

- `azurerm_role_assignment` (at any scope)
- `azuread_directory_role_member`
- `azuread_app_role_assignment`
- `azuread_application_federated_identity_credential`
- `azuread_application_certificate`

A Service Principal or Managed Identity created by this module is enumerable but holds zero RBAC. Any over-permissioned principal that touches a decoy generates an audit-log event while being unable to act on what they find.

## Conditional Access (optional defense-in-depth)

Set `service_principal.conditional_access_block = true` to create an Entra ID Conditional Access policy that blocks all sign-ins targeting the decoy SPs.

**Requirements:** Entra ID P1 or higher in the tenant; `Policy.ReadWrite.ConditionalAccess` Graph permission for the apply principal. Without these, the SPs are still fully inert via the zero-role-assignment rule — CA is an additional layer.

## Cover protection

The module validates all caller-supplied strings and rejects any value containing: `cyngular`, `deception`, `decoy`, `honeytoken`, `bait`, `trap`, `observer` (case-insensitive). This covers `name_prefix`, tag keys/values, `resource_group_name`, blob names, secret values, and the `fake_value` field.

## Usage

```hcl
module "deception" {
  source  = "cyngularsecurity/deception/azure"
  version = "~> 0.1"

  subscription_id     = "00000000-0000-0000-0000-000000000000"
  tenant_id           = "00000000-0000-0000-0000-000000000000"
  resource_group_name = "rg-prod-legacy"

  locations = ["eastus", "westus2"]

  tracking_tag_key   = "cost-center"
  tracking_tag_value = "cc-9842"

  lure_tags = {
    environment = "prod"
    owner       = "legacy-team"
    managed-by  = "terraform"
  }

  service_principal = {
    enabled             = true
    count               = 2
    name_prefix         = "legacy-svc"
    generate_secret     = true   # bait client secret — outputs as sensitive
    secret_expiry_years = 5      # look-legacy; default is deliberately not "tomorrow"
    conditional_access_block = false
  }

  managed_identity = {
    enabled     = true
    count       = 2
    name_prefix = "legacy-identity"
  }

  storage_account = {
    enabled     = true
    count       = 1
    name_prefix = "legacysa"  # 1–11 chars, lowercase alphanumeric only
    # decoy_blobs defaults to built-in set (employees.csv, prod-backup.bak, ...)
  }

  key_vault_secret = {
    enabled     = true
    count       = 1
    name_prefix = "legacy-kv"  # 1–14 chars, must start with a letter
    # fake_value defaults to a generated connection-string-shaped placeholder
  }
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `subscription_id` | `string` | — | Azure subscription for decoys |
| `tenant_id` | `string` | — | Azure AD tenant for the Service Principal |
| `resource_group_name` | `string` | — | Existing RG; module does not create it |
| `locations` | `list(string)` | `["eastus"]` | Regions for Storage and Key Vault (fan-out) |
| `tracking_tag_key` | `string` | — | Tag key applied to every decoy |
| `tracking_tag_value` | `string` | — | Tag value applied to every decoy |
| `lure_tags` | `map(string)` | `{environment="prod", owner="legacy-team"}` | Operational lure tags |
| `service_principal` | object | `{}` (disabled) | SP honeytoken config |
| `managed_identity` | object | `{}` (disabled) | Managed Identity honeytoken config |
| `storage_account` | object | `{}` (disabled) | Storage Account decoy config |
| `key_vault_secret` | object | `{}` (disabled) | Key Vault Secret decoy config |

All per-kind objects share `enabled`, `count`, `name_prefix`. See `variables.tf` for the full shape and validation constraints.

## Outputs

| Name | Description |
|---|---|
| `service_principal_object_ids` | Object IDs keyed by instance (directory audit logs) |
| `service_principal_app_ids` | App (client) IDs keyed by instance (sign-in logs) |
| `service_principal_secrets` | Client secrets keyed by instance — **sensitive** |
| `managed_identity_ids` | Resource IDs keyed by instance |
| `managed_identity_principal_ids` | Principal IDs keyed by instance |
| `storage_account_ids` | Resource IDs keyed by `instance-location` |
| `key_vault_secret_ids` | Versioned secret IDs keyed by `instance-location` |
| `tracking_tag` | `{ key, value }` echoed for platform registration |

## Storage account posture

| Setting | Value | Reason |
|---|---|---|
| `public_network_access_enabled` | `true` | In-tenant data-plane access must reach the account |
| `allow_nested_items_to_be_public` | `false` | No anonymous internet reads |
| `shared_access_key_enabled` | `false` | Force RBAC auth so every data-plane touch is audit-logged |
| `min_tls_version` | `TLS1_2` | Baseline hygiene |
| `network_rules.default_action` | `Allow` | In-tenant RBAC-authorized callers must be able to reach the account |

## Key Vault posture

| Setting | Value | Reason |
|---|---|---|
| `rbac_authorization_enabled` | `true` | RBAC-mode; module creates zero role assignments |
| `public_network_access_enabled` | `true` | In-tenant data-plane access must reach the vault |
| `purge_protection_enabled` | `false` | `terraform destroy` works without a 90-day wait |
| `soft_delete_retention_days` | `7` | Minimum; mandatory in azurerm ≥ 3.0 |

## Naming constraints

| Kind | Azure limit | Module behavior |
|---|---|---|
| Storage account | 3–24 chars, lowercase alphanumeric, globally unique | `name_prefix` (1–11 chars) + 8-char random hex suffix |
| Key Vault | 3–24 chars, alphanumeric + hyphens, start with letter, globally unique | `name_prefix` (1–14 chars) + `-` + 4-char random hex suffix |
| KV secret name | 1–127 chars, `[a-zA-Z0-9-]` | Fixed to `storage-account-key` |
| Managed Identity | 3–128 chars, alphanumeric + `_-.` | `name_prefix-index` |
| App Registration display_name | ≤ 256 chars | `name_prefix-index` |

## Releasing

Pushes to `main` trigger `.github/workflows/publish_tf_module.yml`, which auto-tags `vX.Y.Z` using the built-in `GITHUB_TOKEN` (no `PA_TOKEN` secret required). The [Terraform Registry](https://registry.terraform.io) auto-publishes new tags once the repo is connected via the one-time UI step at `registry.terraform.io`.

## Out of scope (v1)

Management Group / tenant-root policies · Customer-managed encryption keys (CMEK) · Private Endpoints · Diagnostic settings → Log Analytics · Resource Locks · SQL / Cosmos DB / VM snapshot decoys · Steganographic markers · Observer principal / sole-allowed-reader role · Secret distribution (tracked separately, same open question as AWS access keys).
