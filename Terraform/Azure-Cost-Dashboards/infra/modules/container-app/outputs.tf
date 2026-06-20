# Note: We use try() because if count=0, the resource doesn't exist and outputs would fail
output "container_app_id" {
  value = try(azurerm_container_app.enricher[0].id, null)
}
output "container_app_fqdn" { value = try(azurerm_container_app.enricher[0].latest_revision_fqdn, null) }