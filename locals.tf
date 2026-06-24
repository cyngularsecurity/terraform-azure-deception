locals {
  common_tags = merge(
    var.lure_tags,
    { (var.tracking_tag_key) = var.tracking_tag_value },
  )

  # Instance maps — one entry per created resource unit

  sp_instances = var.service_principal.enabled && var.service_principal.count > 0 ? {
    for i in range(var.service_principal.count) : tostring(i) => i
  } : {}

  sp_secret_instances = var.service_principal.generate_secret ? local.sp_instances : {}

  mi_instances = var.managed_identity.enabled && var.managed_identity.count > 0 ? {
    for i in range(var.managed_identity.count) : tostring(i) => i
  } : {}

  # Storage and KV fan out over instance index × location
  _sa_pairs = var.storage_account.enabled && var.storage_account.count > 0 ? flatten([
    for i in range(var.storage_account.count) : [
      for loc in var.locations : {
        key      = "${i}-${replace(loc, " ", "")}"
        idx      = i
        location = loc
      }
    ]
  ]) : []

  sa_instances = { for p in local._sa_pairs : p.key => p }

  _kv_pairs = var.key_vault_secret.enabled && var.key_vault_secret.count > 0 ? flatten([
    for i in range(var.key_vault_secret.count) : [
      for loc in var.locations : {
        key      = "${i}-${replace(loc, " ", "")}"
        idx      = i
        location = loc
      }
    ]
  ]) : []

  kv_instances = { for p in local._kv_pairs : p.key => p }

  # Default decoy blob set — no PII, no real creds, no forbidden tokens

  default_decoy_blobs = [
    {
      name    = "employees.csv"
      content = "id,name,department,email\n1,Jane Smith,Finance,jsmith@corp.local\n2,Bob Chen,Engineering,bchen@corp.local\n3,Maria Lopez,Operations,mlopez@corp.local\n"
    },
    {
      name    = "prod-backup.bak"
      content = "PROD_DB_BACKUP v2.3.1 -- internal use only\nChecksum: 9f4e2a1b\nCreated: 2024-11-15\n[snapshot payload omitted]\n"
    },
    {
      name    = "internal-notes.md"
      content = "# Q3 Infrastructure Notes\n- Legacy IAM roles pending cleanup (owner: ops-team)\n- Storage migration blocked on compliance sign-off\n- Rotate service account keys before EOY\n"
    },
    {
      name    = "azure-keys-backup.json"
      content = "{\"note\":\"manual key backup — rotate before EOY\",\"entries\":[{\"name\":\"storage-primary\",\"status\":\"active\"},{\"name\":\"storage-secondary\",\"status\":\"standby\"}]}\n"
    },
  ]

  effective_blobs = length(var.storage_account.decoy_blobs) > 0 ? var.storage_account.decoy_blobs : local.default_decoy_blobs

  # Blob instances: one resource per (storage_instance_key, blob_index)
  sa_blob_instances = var.storage_account.enabled ? merge([
    for sk in keys(local.sa_instances) : {
      for bi, blob in local.effective_blobs :
      "${sk}-blob${bi}" => {
        storage_key  = sk
        blob_name    = blob.name
        blob_content = blob.content
      }
    }
  ]...) : {}

  # Derived name prefixes — fall back to generic lure names when caller omits

  sp_prefix = var.service_principal.name_prefix != "" ? var.service_principal.name_prefix : "legacy-svc"
  mi_prefix = var.managed_identity.name_prefix != "" ? var.managed_identity.name_prefix : "legacy-identity"
  sa_prefix = var.storage_account.name_prefix != "" ? var.storage_account.name_prefix : "legacysa"
  kv_prefix = var.key_vault_secret.name_prefix != "" ? var.key_vault_secret.name_prefix : "legacy-kv"

  # Secret name inside each vault — looks like a real credential name
  kv_secret_name = "storage-account-key"
}
