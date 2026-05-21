# ==========================================
# SAFE OUTPUTS
# ==========================================
# We use try(resource[0].id, "") to prevent Terraform crashing 
# if a module was skipped because its feature toggle was set to false.

output "core_vnet_id" {
  value = module.vnet_hub.id
}

output "subnet_ids" {
  value = module.vnet_hub.subnet_ids
}

output "nsg_ids" {
  value = {
    web = module.nsg_web.id
    app = module.nsg_app.id
    db  = module.nsg_db.id
  }
}

output "storage_account_name" {
  value = azurerm_storage_account.this.name
}

output "bastion_id" {
  value = try(module.bastion[0].id, "")
}

output "firewall_id" {
  value = try(module.firewall[0].id, "")
}

output "key_vault_id" {
  value = try(module.key_vault[0].id, "")
}

output "log_analytics_id" {
  value = try(module.log_analytics[0].id, "")
}