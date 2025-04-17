output "resource_group" {
  value = azurerm_resource_group.demo_rg.name
}
output "azuread_application_client_id" {
  value = azuread_application.github_oidc_app.application_id
}

output "azuread_service_principal_id" {
  value = azuread_service_principal.github_oidc_sp.id
}

output "azuread_service_principal_object_id" {
  value = azuread_service_principal.github_oidc_sp.object_id
}

output "azuread_service_principal_app_role_id" {
  value = azuread_service_principal.github_oidc_sp_app_role.id
}

output "azuread_service_principal_app_role_object_id" {
  value = azuread_service_principal.github_oidc_sp_app_role.object_id
}
