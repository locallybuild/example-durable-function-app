output "orders_url" {
  description = "POST an order here to start an orchestration; GET /api/orders/{id} reads it back."
  value       = module.durable-function-app.orders_url
}

output "shop_url" {
  description = "The demo page: place an order and watch its orchestration run."
  value       = module.durable-function-app.shop_url
}

output "scheduler_endpoint" {
  description = "The Durable Task Scheduler's endpoint."
  value       = module.durable-function-app.scheduler_endpoint
}

output "task_hub_dashboard_url" {
  description = "The task hub's dashboard."
  value       = module.durable-function-app.task_hub_dashboard_url
}

output "function_app_name" {
  description = "The name of the deployed Function App."
  value       = module.durable-function-app.function_app_name
}
