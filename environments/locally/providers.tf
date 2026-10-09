terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# azapi reads the same ARM_* environment that `locally run` sets, so it talks
# to the same Locally instance azurerm does.
provider "azapi" {}

module "durable-function-app" {
  source = "../../modules/durable-function-app"

  name_prefix = "locally-example-durable"
  location    = "berlin"
  tags = {
    ProvisionedVia = "Terraform"
  }
}
