# This Terraform configuration demonstrates how to create a custom Azure Policy
# that requires a specific tag on all resources within a resource group.
resource "azurerm_resource_group" "demo_rg" {
  name     = "rg-policy-demo"
  location = var.location
}

resource "azurerm_policy_definition" "require_env_tag" {
  name         = "require-env-tag"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "Require Environment Tag"
  description  = "Enforces the existence of an 'Environment' tag on all resources."

  policy_rule = file("${path.module}/policy/require-tags-policy.json")
}

resource "azurerm_policy_assignment" "require_env_tag_assignment" {
  name                 = "require-env-tag-assignment"
  policy_definition_id = azurerm_policy_definition.require_env_tag.id
  scope                = azurerm_resource_group.demo_rg.id
  description          = "Assignment of require-env-tag policy"
  display_name         = "Require Environment Tag Assignment"
}
