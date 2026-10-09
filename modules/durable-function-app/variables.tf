variable "name_prefix" {
  description = "The prefix used for all resources in this example."
  type        = string
}

variable "location" {
  description = "The region where these resources should be deployed."
  type        = string
}

variable "tags" {
  description = "A mapping of tags which should be applied to each of the resources."
  type        = map(string)
  default     = {}
}

variable "service_plan_sku" {
  description = "App Service plan SKU (Linux)."
  type        = string
  default     = "B1"
}

variable "task_hub_name" {
  description = "The task hub on the scheduler that the Function App runs its orchestrations in. Must match hubName in function/host.json."
  type        = string
  default     = "orders"
}
