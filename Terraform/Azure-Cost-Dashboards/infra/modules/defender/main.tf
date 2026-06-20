# Enterprise: Microsoft Defender for Cloud enablement
# FinOps is linked to security (e.g., exposed storage accounts lead to crypto-mining cost spikes).
resource "azurerm_security_center_subscription_pricing" "vms" {
  tier          = "Standard"
  resource_type = "VirtualMachines"
}

resource "azurerm_security_center_subscription_pricing" "storage" {
  tier          = "Standard"
  resource_type = "StorageAccounts"
}

resource "azurerm_security_center_subscription_pricing" "app_services" {
  tier          = "Standard"
  resource_type = "AppServices"
}

resource "azurerm_security_center_subscription_pricing" "key_vaults" {
  tier          = "Standard"
  resource_type = "KeyVaults"
}

# Enterprise: Defender for Containers (Covers AKS, ACR, and external K8s)
resource "azurerm_security_center_subscription_pricing" "containers" {
  tier          = "Standard"
  resource_type = "Containers" # Unified Defender for Containers plan
}

# Enterprise: Defender for Container Registries (Scans Python Docker images for CVEs)
resource "azurerm_security_center_subscription_pricing" "container_registry" {
  tier          = "Standard"
  resource_type = "ContainerRegistry"
}

# (Keep the existing VMs, Storage, AppServices, KeyVaults pricing resources here)