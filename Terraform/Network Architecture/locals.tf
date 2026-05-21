# ==========================================
# NAMING ENGINE & LOCAL VARIABLES
# ==========================================

# Translates long Azure region names into short codes for resource naming.
locals {
  location_map = {
    "eastus"       = "eus"
    "eastus2"      = "eus2"
    "westus2"      = "wus2"
    "centralus"    = "cus"
    "westeurope"   = "weu"
    "northeurope"  = "neu"
    "southeastasia"= "sea"
  }
  
  # Looks up the short code. If region isn't in map, defaults to "reg".
  loc_abbr = try(local.location_map[replace(lower(var.location), " ", "")], "reg")
  env_abbr = substr(var.environment, 0, 3)
  
  # Merges user tags with our mandatory tags.
  default_tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.prefix
  })

  # The single source of truth for ALL resource names in this project.
  name = {
    vnet1         = "${var.prefix}-${local.env_abbr}-vnet-hub-${local.loc_abbr}"
    vnet2         = "${var.prefix}-${local.env_abbr}-vnet-spoke-${local.loc_abbr}"
    nsg_web       = "${var.prefix}-${local.env_abbr}-nsg-web-${local.loc_abbr}"
    nsg_app       = "${var.prefix}-${local.env_abbr}-nsg-app-${local.loc_abbr}"
    nsg_db        = "${var.prefix}-${local.env_abbr}-nsg-db-${local.loc_abbr}"
    nsg_secondary = "${var.prefix}-${local.env_abbr}-nsg-spoke-${local.loc_abbr}"
    storage       = "${var.prefix}${local.env_abbr}st${substr(random_id.storage.hex, 0, 8)}"
    pe_storage    = "${var.prefix}-${local.env_abbr}-pe-storage-${local.loc_abbr}"
    vpn_gw        = "${var.prefix}-${local.env_abbr}-vpngw-${local.loc_abbr}"
    vpn_pip       = "${var.prefix}-${local.env_abbr}-pip-vpngw-${local.loc_abbr}"
    bastion       = "${var.prefix}-${local.env_abbr}-bas-${local.loc_abbr}"
    bastion_pip   = "${var.prefix}-${local.env_abbr}-pip-bas-${local.loc_abbr}"
    firewall      = "${var.prefix}-${local.env_abbr}-afw-${local.loc_abbr}"
    firewall_pip  = "${var.prefix}-${local.env_abbr}-pip-afw-${local.loc_abbr}"
    key_vault     = "${var.prefix}-${local.env_abbr}-kv-${local.loc_abbr}"
    log_analytics = "${var.prefix}-${local.env_abbr}-law-${local.loc_abbr}"
  }
}