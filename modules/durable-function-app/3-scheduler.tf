# ---------------------------------------------------------------------------
# The Durable Task Scheduler and its task hub.
#
# The azurerm provider has no resources for Microsoft.DurableTask yet, so the
# scheduler is declared with azapi against the provider's API. The endpoint
# comes back from the create and is what the Function App connects to.
# ---------------------------------------------------------------------------
resource "azapi_resource" "scheduler" {
  type      = "Microsoft.DurableTask/schedulers@2025-04-01-preview"
  name      = "${var.name_prefix}-scheduler"
  location  = azurerm_resource_group.main.location
  parent_id = azurerm_resource_group.main.id
  tags      = var.tags

  body = {
    properties = {
      ipAllowlist = ["0.0.0.0/0"]
      sku = {
        name     = "Dedicated"
        capacity = 1
      }
    }
  }

  response_export_values = ["properties.endpoint"]
}

resource "azapi_resource" "task_hub" {
  type      = "Microsoft.DurableTask/schedulers/taskHubs@2025-04-01-preview"
  name      = var.task_hub_name
  parent_id = azapi_resource.scheduler.id

  body = {
    properties = {}
  }

  response_export_values = ["properties.dashboardUrl"]
}
