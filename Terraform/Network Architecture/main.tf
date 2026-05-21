# ==========================================
# THE ORCHESTRATOR
# ==========================================

# --- LOG ANALYTICS (Must deploy first if others depend on it) ---
module "log_analytics" {
  count               = var.deploy_log_analytics ? 1 : 0
  source              = "./modules/loganalytics"
  name                = local.name.log_analytics
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.default_tags
}

# --- NSGS (Dynamic Rule Generation) ---
module "nsg_web" {
  source              = "./modules/nsg"
  name                = local.name.nsg_web
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.default_tags
  tier_type           = "web"
  management_ip       = var.management_public_ip

  web_cidr   = var.subnets.web
  app_cidr   = var.subnets.app
  spoke_cidr = var.vnet2_address_space
  hub_cidr   = var.vnet1_address_space
  vpn_pool   = var.vpn_client_pool
}

module "nsg_app" {
  source              = "./modules/nsg"
  name                = local.name.nsg_app
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.default_tags
  tier_type           = "app"
  management_ip       = var.management_public_ip
  vpn_pool            = var.vpn_client_pool
  web_cidr            = var.subnets.web
  app_cidr            = var.subnets.app
  spoke_cidr          = var.vnet2_address_space
  hub_cidr            = var.vnet1_address_space
}

module "nsg_db" {
  source              = "./modules/nsg"
  name                = local.name.nsg_db
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.default_tags
  tier_type           = "database"
  management_ip       = var.management_public_ip
  vpn_pool            = var.vpn_client_pool
  app_cidr            = var.subnets.app
  spoke_cidr          = var.vnet2_address_space
  web_cidr            = var.subnets.web
  hub_cidr            = var.vnet1_address_space
}

module "nsg_secondary" {
  source              = "./modules/nsg"
  name                = local.name.nsg_secondary
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.default_tags
  tier_type           = "secondary"
  management_ip       = var.management_public_ip
  hub_cidr            = var.vnet1_address_space
  web_cidr            = var.subnets.web
  app_cidr            = var.subnets.app
  spoke_cidr          = var.vnet2_address_space
  vpn_pool            = var.vpn_client_pool
}

# --- VNETS ---
module "vnet_hub" {
  source              = "./modules/vnet"
  name                = local.name.vnet1
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.vnet1_address_space
  tags                = local.default_tags

  subnets = {
    web = var.subnets.web
    app = var.subnets.app
    db  = var.subnets.db
    pe  = var.subnets.pe
  }

  nsg_ids = {
    web = module.nsg_web.id
    app = module.nsg_app.id
    db  = module.nsg_db.id
  }

  deploy_vpn      = var.deploy_vpn
  deploy_bastion  = var.deploy_bastion
  deploy_firewall = var.deploy_firewall && var.deploy_log_analytics

  gateway_cidr  = var.gateway_cidr
  bastion_cidr  = var.bastion_cidr
  firewall_cidr = var.firewall_cidr

  service_endpoints = {
    "snet-web" = ["Microsoft.Storage"]
    "snet-app" = ["Microsoft.Storage"]
  }
}

module "vnet_spoke" {
  source              = "./modules/vnet"
  name                = local.name.vnet2
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.vnet2_address_space
  tags                = local.default_tags

  subnets = {
    workload = var.subnets.secondary
  }

  nsg_ids = {
    workload = module.nsg_secondary.id
  }

  deploy_vpn      = false
  deploy_bastion  = false
  deploy_firewall = false

  gateway_cidr  = var.gateway_cidr   # ← dedicated variable (unused but required by module)
  bastion_cidr  = var.bastion_cidr
  firewall_cidr = var.firewall_cidr
}

# --- VNET PEERING ---
module "peering" {
  source                = "./modules/peering"
  resource_group_name   = var.resource_group_name
  hub_vnet_id           = module.vnet_hub.id
  hub_vnet_name         = module.vnet_hub.name
  spoke_vnet_id         = module.vnet_spoke.id
  spoke_vnet_name       = module.vnet_spoke.name
  allow_gateway_transit = var.deploy_vpn

  depends_on = [module.vnet_hub, module.vnet_spoke]
}

# --- STORAGE ACCOUNT ---
resource "azurerm_storage_account" "this" {
  name                          = local.name.storage
  resource_group_name           = var.resource_group_name
  location                      = var.location
  account_tier                  = "Standard"
  account_replication_type      = "LRS"
  account_kind                  = "StorageV2"
  access_tier                   = "Hot"
  public_network_access_enabled = false
  min_tls_version               = "TLS1_2"
  tags                          = local.default_tags
}

resource "azurerm_storage_account_network_rules" "this" {
  storage_account_id = azurerm_storage_account.this.id
  default_action     = "Deny"
  bypass             = ["AzureServices"]
  virtual_network_subnet_ids = [
    module.vnet_hub.subnet_ids["snet-web"],   # FIX: vnet module prefixes with "snet-"
    module.vnet_hub.subnet_ids["snet-app"],   # FIX: vnet module prefixes with "snet-"
  ]
}

# --- PRIVATE ENDPOINTS ---
module "private_endpoint_storage" {
  count               = var.deploy_private_endpoints ? 1 : 0
  source              = "./modules/endpoints"
  name                = local.name.pe_storage
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.default_tags

  target_resource_id   = azurerm_storage_account.this.id
  target_resource_name = azurerm_storage_account.this.name
  group_id             = "blob"
  subnet_id            = module.vnet_hub.subnet_ids["snet-pe"]   # FIX: vnet module prefixes with "snet-"
  vnet_ids             = [module.vnet_hub.id, module.vnet_spoke.id]
  dns_zone_name        = "privatelink.blob.core.windows.net"
}

# --- VPN GATEWAY ---
module "vpn" {
  count               = var.deploy_vpn && var.vpn_root_cert_data != "" ? 1 : 0
  source              = "./modules/vpn"
  name                = local.name.vpn_gw
  public_ip_name      = local.name.vpn_pip
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = module.vnet_hub.subnet_ids["GatewaySubnet"]  # no snet- prefix — Azure reserved name
  tags                = local.default_tags
  vpn_client_pool     = var.vpn_client_pool
  vpn_root_cert_name  = var.vpn_root_cert_name
  vpn_root_cert_data  = trimspace(var.vpn_root_cert_data)
}

# --- AZURE BASTION ---
module "bastion" {
  count               = var.deploy_bastion ? 1 : 0
  source              = "./modules/bastion"
  name                = local.name.bastion
  public_ip_name      = local.name.bastion_pip
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = module.vnet_hub.subnet_ids["AzureBastionSubnet"]  # no snet- prefix — Azure reserved name
  tags                = local.default_tags
}

# --- AZURE FIREWALL ---
module "firewall" {
  count               = var.deploy_firewall && var.deploy_log_analytics ? 1 : 0
  source              = "./modules/firewall"
  name                = local.name.firewall
  public_ip_name      = local.name.firewall_pip
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = module.vnet_hub.subnet_ids["AzureFirewallSubnet"] # no snet- prefix — Azure reserved name
  log_analytics_id    = module.log_analytics[0].id
  tags                = local.default_tags
}

# --- KEY VAULT ---
module "key_vault" {
  count               = var.deploy_key_vault ? 1 : 0
  source              = "./modules/keyvault"
  name                = local.name.key_vault
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.default_tags
  tenant_id           = data.azurerm_client_config.current.tenant_id
  object_id           = data.azurerm_client_config.current.object_id
}
