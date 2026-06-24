resource "azuread_application" "decoy" {
  for_each     = local.sp_instances
  display_name = "${local.sp_prefix}-${each.key}"
}

resource "azuread_service_principal" "decoy" {
  for_each  = local.sp_instances
  client_id = azuread_application.decoy[each.key].client_id
}

resource "time_offset" "sp_secret_expiry" {
  for_each     = local.sp_secret_instances
  offset_years = var.service_principal.secret_expiry_years
}

# Optional bait client secret — only when generate_secret = true
resource "azuread_application_password" "decoy" {
  for_each       = local.sp_secret_instances
  display_name   = "api-key-${each.key}"
  application_id = azuread_application.decoy[each.key].id
  end_date       = time_offset.sp_secret_expiry[each.key].rfc3339
}

resource "azuread_conditional_access_policy" "decoy_block" {
  count        = var.service_principal.enabled && var.service_principal.conditional_access_block && var.service_principal.count > 0 ? 1 : 0
  display_name = "${local.sp_prefix}-access-control"
  state        = "enabled"

  conditions {
    applications {
      included_applications = [for k, v in azuread_application.decoy : v.client_id]
    }
    users {
      included_users = ["All"]
    }
    client_app_types = ["all"]
  }

  grant_controls {
    operator          = "OR"
    built_in_controls = ["block"]
  }

  depends_on = [azuread_service_principal.decoy]
}
