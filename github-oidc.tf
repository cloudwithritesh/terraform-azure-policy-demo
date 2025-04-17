# This Terraform configuration sets up an Azure AD application and service principal
# for GitHub Actions OIDC authentication, and assigns the necessary roles.
# It also assigns the Contributor role at the subscription level and the Storage Blob Data Contributor role
# at the storage account level for Terraform state management.
data "azurerm_subscription" "current" {}

resource "azuread_application" "github_oidc_app" {
  display_name = "terraform-oidc-app"
}

resource "azuread_service_principal" "github_oidc_sp" {
  application_id = azuread_application.github_oidc_app.application_id
}

resource "azuread_application_federated_identity_credential" "github_oidc" {
  application_object_id = azuread_application.github_oidc_app.object_id
  display_name          = "github-oidc"
  description           = "OIDC login from GitHub Actions"
  audiences             = ["api://AzureADTokenExchange"]
  issuer                = "https://token.actions.githubusercontent.com"
  subject               = "repo:<GITHUB_ORG>/<REPO>:ref:refs/heads/main"
}

# Contributor Role Assignment at Subscription Scope
resource "azurerm_role_assignment" "contributor" {
  principal_id         = azuread_service_principal.github_oidc_sp.object_id
  role_definition_name = "Contributor"
  scope                = data.azurerm_subscription.current.id
}

# Storage Blob Data Contributor on the Terraform state storage account
data "azurerm_storage_account" "tfstate" {
  name                = "<STORAGE_ACCOUNT_NAME>"
  resource_group_name = "<STORAGE_ACCOUNT_RG>"
}

resource "azurerm_role_assignment" "storage_blob_contributor" {
  principal_id         = azuread_service_principal.github_oidc_sp.object_id
  role_definition_name = "Storage Blob Data Contributor"
  scope                = data.azurerm_storage_account.tfstate.id
}
