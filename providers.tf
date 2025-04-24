# terraform {
#   required_providers {
#     azuread = {
#       source  = "hashicorp/azuread"
#       version = "~> 2.47.0"
#     }
#   }
#   backend "azurerm" {
#     resource_group_name  = "tfstate-rg"
#     storage_account_name = "tfstatehugdemo2304"
#     container_name       = "tfstate"
#     key                  = "terraform.tfstate"
#   }
# }

# provider "azuread" {}

# provider "azurerm" {
#   features {}
#   # Option 1: Explicitly set subscription_id
#   #   subscription_id = var.subscription_id

#   # Option 2: Use environment variable ARM_SUBSCRIPTION_ID
#   use_oidc = true
# }

# data "azurerm_subscription" "current" {}
