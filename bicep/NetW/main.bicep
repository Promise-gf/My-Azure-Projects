@description('Azure region')
param location string = resourceGroup().location

@description('Naming prefix (e.g., corp, projx)')
@minLength(2)
@maxLength(10)
param prefix string = 'net'

@description('Environment (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Primary/Secondary VNet Address Spaces')
param vnet1AddressSpace string = '10.10.0.0/16'
param vnet2AddressSpace string = '10.20.0.0/16'

@description('Subnet CIDRs')
param subnets object = {
  web: '10.10.1.0/24'
  app: '10.10.2.0/24'
  db: '10.10.3.0/24'
  pe: '10.10.4.0/24'
  gateway: '10.10.255.224/27'
  AzureBastionSubnet: '10.10.254.0/26'
  AzureFirewallSubnet: '10.10.253.0/26'
  secondary: '10.20.1.0/24'
}

@description('Mgmt IP for RDP/SSH — defaults to VPN client pool')
param managementPublicIp string = '192.168.10.0/24'

@description('VPN Client Pool')
param vpnClientPool string = '192.168.10.0/24'

@description('Feature Toggles')
param deployVpn bool = true
param deployPrivateEndpoints bool = true
param deployBastion bool = true
param deployFirewall bool = true
param deployKeyVault bool = true
param deployLogAnalytics bool = true

@secure()
@description('Base64 VPN Root Cert')
param vpnRootCertData string = ''
param vpnRootCertName string = 'P2S-Root-Cert'

param tags object = {}

// ==========================================
// CALL NAMING MODULE
// ==========================================
module naming 'modules/naming.bicep' = {
  name: 'naming-${deployment().name}'
  params: {
    prefix: prefix
    environment: environment
    location: location
  }
}

var defaultTags = union(tags, { Environment: environment, Project: prefix })

// ==========================================
// LOG ANALYTICS (deploy first — others depend on it)
// ==========================================
module logAnalytics 'modules/loganalytics.bicep' = if (deployLogAnalytics) {
  name: 'log-analytics-deploy'
  params: {
    name: naming.outputs.logAnalytics
    location: location
    tags: defaultTags
  }
}

// ==========================================
// CALL NSG MODULES
// ==========================================
module nsgWeb 'modules/nsg.bicep' = {
  name: 'nsg-web-deploy'
  params: {
    name: naming.outputs.nsgWeb
    location: location
    tierType: 'web'
    managementPublicIp: managementPublicIp
    tags: defaultTags
  }
}

module nsgApp 'modules/nsg.bicep' = {
  name: 'nsg-app-deploy'
  params: {
    name: naming.outputs.nsgApp
    location: location
    tierType: 'app'
    managementPublicIp: managementPublicIp
    vpnClientPool: vpnClientPool
    webSubnetPrefix: subnets.web
    tags: defaultTags
  }
}

module nsgDb 'modules/nsg.bicep' = {
  name: 'nsg-db-deploy'
  params: {
    name: naming.outputs.nsgDb
    location: location
    tierType: 'database'
    managementPublicIp: managementPublicIp
    vpnClientPool: vpnClientPool
    appSubnetPrefix: subnets.app
    secondaryVnetPrefix: vnet2AddressSpace
    tags: defaultTags
  }
}

module nsgSecondary 'modules/nsg.bicep' = {
  name: 'nsg-secondary-deploy'
  params: {
    name: naming.outputs.nsgSecondary
    location: location
    tierType: 'secondary'
    managementPublicIp: managementPublicIp
    primaryVnetPrefix: vnet1AddressSpace
    tags: defaultTags
  }
}

// ==========================================
// CALL VNET MODULES
// ==========================================
module vnet1 'modules/vnet.bicep' = {
  name: 'vnet-primary-deploy'
  params: {
    name: naming.outputs.vnet1
    location: location
    addressSpace: vnet1AddressSpace
    subnets: subnets
    nsgAssignments: {
      'snet-web': nsgWeb.outputs.nsgId
      'snet-app': nsgApp.outputs.nsgId
      'snet-db': nsgDb.outputs.nsgId
    }
    deployVpn: deployVpn
    tags: defaultTags
  }
}

module vnet2 'modules/vnet.bicep' = {
  name: 'vnet-secondary-deploy'
  params: {
    name: naming.outputs.vnet2
    location: location
    addressSpace: vnet2AddressSpace
    subnets: { workload: subnets.secondary }
    nsgAssignments: {
      'snet-workload': nsgSecondary.outputs.nsgId
    }
    deployVpn: false
    tags: defaultTags
  }
}

// ==========================================
// CALL PEERING MODULE
// ==========================================
module peering 'modules/peering.bicep' = {
  name: 'peering-deploy'
  params: {
    vnet1Id: vnet1.outputs.vnetId
    vnet2Id: vnet2.outputs.vnetId
    allowGatewayTransit: deployVpn
  }
}

// ==========================================
// AZURE BASTION
// ==========================================
module bastion 'modules/bastion.bicep' = if (deployBastion) {
  name: 'bastion-deploy'
  params: {
    name: naming.outputs.bastion
    location: location
    subnetId: vnet1.outputs.subnetIds.AzureBastionSubnet
    tags: defaultTags
  }
}

// ==========================================
// AZURE FIREWALL
// ==========================================
module firewall 'modules/firewall.bicep' = if (deployFirewall && deployLogAnalytics) {
  name: 'firewall-deploy'
  params: {
    name: naming.outputs.firewall
    location: location
    subnetId: vnet1.outputs.subnetIds.AzureFirewallSubnet
    logAnalyticsWorkspaceId: any(logAnalytics).outputs.workspaceId
    tags: defaultTags
  }
}

// ==========================================
// KEY VAULT
// ==========================================
module keyVault 'modules/keyvault.bicep' = if (deployKeyVault) {
  name: 'keyvault-deploy'
  params: {
    name: naming.outputs.keyVault
    location: location
    tags: defaultTags
  }
}

// ==========================================
// STORAGE & PRIVATE ENDPOINTS
// ==========================================
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: '${prefix}${substring(environment, 0, 3)}st${substring(uniqueString(resourceGroup().id), 0, 8)}'
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  tags: defaultTags
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      virtualNetworkRules: [
        {
          id: vnet1.outputs.subnetIds.web
          action: 'Allow'
        }
        {
          id: vnet1.outputs.subnetIds.app
          action: 'Allow'
        }
      ]
    }
  }
}

module privEndpoint 'modules/endpoints.bicep' = if (deployPrivateEndpoints) {
  name: 'pe-storage-deploy'
  params: {
    name: naming.outputs.privEndpoint
    location: location
    targetResourceId: storageAccount.id
    groupId: 'blob'
    subnetId: vnet1.outputs.subnetIds.privateEndpoints
    vnetIds: [ vnet1.outputs.vnetId, vnet2.outputs.vnetId ]
    dnsZoneName: 'privatelink.blob.${az.environment().suffixes.storage}'
    targetResourceName: storageAccount.name
    tags: defaultTags
  }
}

// ==========================================
// VPN GATEWAY
// ==========================================
module vpn 'modules/vpn.bicep' = if (deployVpn && contains(vpnRootCertData, '==')) {
  name: 'vpn-deploy'
  params: {
    name: naming.outputs.vpnGw
    publicIpName: naming.outputs.vpnPip
    location: location
    gatewaySubnetId: vnet1.outputs.subnetIds.gateway
    vpnClientPool: vpnClientPool
    vpnRootCertData: vpnRootCertData
    vpnRootCertName: vpnRootCertName
    tags: defaultTags
  }
}

// ==========================================
// OUTPUTS
// ==========================================
// ==========================================
// OUTPUTS
// ==========================================
output coreVnetId string = vnet1.outputs.vnetId
output subnetIds object = vnet1.outputs.subnetIds
output nsgIds object = {
  web: nsgWeb.outputs.nsgId
  app: nsgApp.outputs.nsgId
  db: nsgDb.outputs.nsgId
}
output bastionId string = deployBastion ? any(bastion).outputs.bastionId : ''
output firewallId string = (deployFirewall && deployLogAnalytics) ? any(firewall).outputs.firewallId : ''
output keyVaultId string = deployKeyVault ? any(keyVault).outputs.keyVaultId : ''
output logAnalyticsId string = deployLogAnalytics ? any(logAnalytics).outputs.workspaceId : ''
