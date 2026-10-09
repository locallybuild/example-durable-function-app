# ---------------------------------------------------------------------------
# Storage Account - the Functions host's own storage (keys, locks, timers for
# non-durable triggers). The orchestration state itself lives on the scheduler.
# ---------------------------------------------------------------------------
resource "azurerm_storage_account" "main" {
  name                     = replace("${var.name_prefix}sa", "-", "")
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags                     = var.tags
}
