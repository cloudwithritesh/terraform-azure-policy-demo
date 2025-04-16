terraform {
  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "tfstatestorage1234"
    container_name       = "tfstate"
    key                  = "azure-policy-demo.terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
}
