resource "azurerm_user_assigned_identity" "decoy" {
  for_each            = local.mi_instances
  name                = "${local.mi_prefix}-${each.key}"
  resource_group_name = var.resource_group_name
  location            = var.locations[0]
  tags                = local.common_tags

  # Never associated with any compute resource — the free-standing MI is the lure.
  # No azurerm_role_assignment, no azurerm_federated_identity_credential created.
}
