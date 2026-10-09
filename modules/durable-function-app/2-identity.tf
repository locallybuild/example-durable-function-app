# ---------------------------------------------------------------------------
# The Function App's identity, and the role that lets it use the scheduler.
# On Azure the Durable Task Scheduler accepts only Entra tokens, and the
# "Durable Task Data Contributor" role is what a worker needs on the scheduler.
# ---------------------------------------------------------------------------
resource "azurerm_user_assigned_identity" "function" {
  name                = "${var.name_prefix}-identity"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = var.tags
}

resource "azurerm_role_assignment" "scheduler" {
  scope                = azapi_resource.scheduler.id
  role_definition_name = "Durable Task Data Contributor"
  principal_id         = azurerm_user_assigned_identity.function.principal_id
}

resource "azurerm_role_assignment" "storage" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azurerm_user_assigned_identity.function.principal_id
}

resource "azurerm_role_assignment" "storage_queue" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = azurerm_user_assigned_identity.function.principal_id
}
