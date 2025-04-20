# # This Terraform configuration demonstrates how to create a custom Azure Policy
# # that requires a specific tag on all resources within a resource group.

# resource "azurerm_resource_group" "demo_rg" {
#   name     = "rg-policy-demo"
#   location = var.location
# }

# resource "azurerm_policy_definition" "require_env_tag" {
#   name         = "require-env-tag"
#   policy_type  = "Custom"
#   mode         = "All"
#   display_name = "Require Environment Tag"
#   description  = "Enforces the existence of an 'Environment' tag on all resources."

#   parameters  = jsonencode({})
#   policy_rule = file("${path.module}/policy/require-tags-policy.json")
# }

# resource "azurerm_resource_group_policy_assignment" "require_env_tag_assignment" {
#   name                 = "require-env-tag-assignment"
#   policy_definition_id = azurerm_policy_definition.require_env_tag.id
#   resource_group_id    = azurerm_resource_group.demo_rg.id
#   description          = "Assignment of require-env-tag policy"
#   display_name         = "Require Environment Tag Assignment"
# }

# resource "azurerm_policy_definition" "allowed_regions" {
#   name         = "allowed-regions-policy"
#   policy_type  = "Custom"
#   mode         = "All"
#   display_name = "Allowed Regions Policy"
#   description  = "This policy restricts resource deployment to specified Azure regions."

#   metadata = jsonencode({
#     version  = "1.0.0"
#     category = "Locations"
#   })

#   parameters = jsonencode({
#     allowedLocations = {
#       type = "Array"
#       metadata = {
#         description = "The list of allowed locations for resources."
#         displayName = "Allowed locations"
#       }
#       defaultValue = [var.location]
#     }
#   })

#   policy_rule = file("${path.module}/policy/allowed-regions-policy.json")
# }

# resource "azurerm_subscription_policy_assignment" "allowed_regions" {
#   name                 = "allowed-regions-assignment"
#   policy_definition_id = azurerm_policy_definition.allowed_regions.id
#   subscription_id      = data.azurerm_subscription.current.id
#   description          = "Assignment of allowed-regions policy at subscription level"
#   display_name         = "Allowed Regions Policy Assignment"

#   parameters = jsonencode({
#     allowedLocations = {
#       value = [var.location]
#     }
#   })
# }
