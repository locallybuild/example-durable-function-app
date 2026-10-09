# ---------------------------------------------------------------------------
# App Service Plan - hosts the Function App
# ---------------------------------------------------------------------------
resource "azurerm_service_plan" "main" {
  name                = "${var.name_prefix}-plan"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.service_plan_sku
}

# ---------------------------------------------------------------------------
# Function App package - zips the published output from the inside, so
# host.json and the worker assembly land at the root of the archive. Run
# `dotnet publish -c Release -o publish` in function/ first.
# ---------------------------------------------------------------------------
data "archive_file" "function" {
  type        = "zip"
  source_dir  = local.publish_dir
  output_path = "${path.module}/../../.build/function-${local.publish_hash}.zip"
}

# ---------------------------------------------------------------------------
# The Function App, with its code and the scheduler connection.
#
# host.json selects the azureManaged storage provider and names the app
# setting that holds the connection string; DURABLE_TASK_SCHEDULER_CONNECTION_STRING
# is the name the Durable extension documents. The identity's client ID is in
# the connection string because the identity is user-assigned.
# ---------------------------------------------------------------------------
resource "azurerm_linux_function_app" "main" {
  name                = "${var.name_prefix}-func"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main.id
  https_only          = true
  tags                = var.tags

  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key

  zip_deploy_file = data.archive_file.function.output_path

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.function.id]
  }

  site_config {
    always_on = true

    application_stack {
      dotnet_version              = "8.0"
      use_dotnet_isolated_runtime = true
    }
  }

  app_settings = {
    FUNCTIONS_WORKER_RUNTIME = "dotnet-isolated"

    # Required by the provider whenever zip_deploy_file is set.
    WEBSITE_RUN_FROM_PACKAGE = "1"

    # The app targets .NET 8. On a machine that has only a newer .NET runtime
    # installed, this is the dotnet host's own setting for starting it there
    # (it is harmless where .NET 8 is present).
    DOTNET_ROLL_FORWARD = "LatestMajor"

    # The Durable Task Scheduler the orchestrations run on.
    DURABLE_TASK_SCHEDULER_CONNECTION_STRING = "Endpoint=${local.scheduler_endpoint};TaskHub=${azapi_resource.task_hub.name};Authentication=ManagedIdentity;ClientID=${azurerm_user_assigned_identity.function.client_id}"

    # The demo page at /api/shop links to the task hub's dashboard.
    TASK_HUB_DASHBOARD_URL = azapi_resource.task_hub.output.properties.dashboardUrl
  }

  depends_on = [
    azurerm_role_assignment.scheduler,
  ]
}
