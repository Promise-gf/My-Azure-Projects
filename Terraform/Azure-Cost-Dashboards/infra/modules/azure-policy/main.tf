resource "azurerm_policy_definition" "mandatory_finops_tags" {
  name         = "deny-missing-finops-tags"
  policy_type  = "Custom"
  mode         = "Indexed" # Only applies to resources that support tags and location
  display_name = "Enforce mandatory FinOps tags (Department, CostCenter)"
  description  = "Denies resource creation if Department and CostCenter tags are not specified or are empty."

  policy_rule = jsonencode({
    if = {
      anyOf = [
        # Check if Department tag is missing
        {
          field = "tags['Department']"
          exists = false
        },
        # Check if Department tag is empty string
        {
          value = "tags['Department']"
          equals = ""
        },
        # Check if CostCenter tag is missing
        {
          field = "tags['CostCenter']"
          exists = false
        },
        # Check if CostCenter tag is empty string
        {
          value = "tags['CostCenter']"
          equals = ""
        }
      ]
    }
    then = {
      effect = "deny"
    }
  })

  parameters = jsonencode({}) # No parameters needed, hardcoding the tag keys for strict governance
}

resource "azurerm_policy_assignment" "finops_tags" {
  name                 = "finops-tag-enforcement"
  display_name         = "Enforce FinOps Tags"
  policy_definition_id = azurerm_policy_definition.mandatory_finops_tags.id
  scope                = var.scope_id
  description          = "Ensures all indexed resources have Department and CostCenter tags for cost attribution."
}