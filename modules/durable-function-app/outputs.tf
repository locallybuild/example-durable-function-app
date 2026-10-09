output "orders_url" {
  description = "POST an order here to start an orchestration; GET /api/orders/{id} reads it back."
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api/orders"
}

output "shop_url" {
  description = "The demo page: place an order and watch its orchestration run."
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api/shop"
}

output "scheduler_endpoint" {
  description = "The Durable Task Scheduler's endpoint, which the Function App and any Durable Task SDK client connect to."
  value       = local.scheduler_endpoint
}

output "task_hub_dashboard_url" {
  description = "The task hub's dashboard: every orchestration on the hub, with its history."
  value       = azapi_resource.task_hub.output.properties.dashboardUrl
}

output "function_app_name" {
  description = "The name of the deployed Function App."
  value       = azurerm_linux_function_app.main.name
}

output "resource_group" {
  description = "The resource group containing the deployed resources."
  value       = azurerm_resource_group.main.name
}
