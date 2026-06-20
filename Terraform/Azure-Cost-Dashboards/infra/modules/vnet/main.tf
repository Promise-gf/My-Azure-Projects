# ── Virtual Network ────────────────────────────────────────────────────────────

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.name_prefix}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.address_space]
  tags                = var.default_tags
}

# ── Function App Subnet (delegated) ───────────────────────────────────────────

resource "azurerm_subnet" "function" {
  name                 = "snet-func-${var.environment}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.function_subnet_prefix]

  delegation {
    name = "delegation"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# ── Private Endpoint Subnet ────────────────────────────────────────────────────

resource "azurerm_subnet" "private_endpoints" {
  name                 = "snet-pe-${var.environment}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.pe_subnet_prefix]

  # Correct attribute name for azurerm provider >= 3.90
  private_endpoint_network_policies = "Disabled"
}

# ── NSG: Defence in Depth for Private Endpoint Subnet ─────────────────────────

resource "azurerm_network_security_group" "pe_nsg" {
  name                = "nsg-pe-${var.name_prefix}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.default_tags

  # Allow inbound ONLY from the Function App subnet
  security_rule {
    name                       = "Allow-Function-To-PE"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.function_subnet_prefix
    destination_address_prefix = var.pe_subnet_prefix
  }

  # Allow Azure Monitor and platform health probes
  security_rule {
    name                       = "Allow-AzureMonitor"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "AzureMonitor"
    destination_address_prefix = "*"
  }

  # Allow Azure load balancer health probes
  security_rule {
    name                       = "Allow-AzureLoadBalancer"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  # Explicit deny all — defence in depth
  security_rule {
    name                       = "Deny-All-Other-Inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# ── Bind NSG to Private Endpoint Subnet ───────────────────────────────────────

resource "azurerm_subnet_network_security_group_association" "pe_nsg_assoc" {
  subnet_id                 = azurerm_subnet.private_endpoints.id
  network_security_group_id = azurerm_network_security_group.pe_nsg.id
}