param name string
param location string
param tierType string
param managementPublicIp string
param vpnClientPool string = ''
param webSubnetPrefix string = ''
param appSubnetPrefix string = ''
param secondaryVnetPrefix string = ''
param primaryVnetPrefix string = ''
param tags object = {}

var denyAll = {
  name: 'DenyAllInbound'
  properties: {
    protocol: '*'
    sourceAddressPrefix: '*'
    sourcePortRange: '*'
    destinationAddressPrefix: '*'
    destinationPortRange: '*'
    access: 'Deny'
    priority: 4096
    direction: 'Inbound'
  }
}

var rules = tierType == 'web' ? [
  {
    name: 'AllowHTTP'
    properties: {
      protocol: 'Tcp'
      sourceAddressPrefix: 'Internet'
      sourcePortRange: '*'
      destinationAddressPrefix: '*'
      destinationPortRange: '80'
      access: 'Allow'
      priority: 100
      direction: 'Inbound'
    }
  }
  {
    name: 'AllowHTTPS'
    properties: {
      protocol: 'Tcp'
      sourceAddressPrefix: 'Internet'
      sourcePortRange: '*'
      destinationAddressPrefix: '*'
      destinationPortRange: '443'
      access: 'Allow'
      priority: 110
      direction: 'Inbound'
    }
  }
  {
    name: 'AllowMgmt'
    properties: {
      protocol: 'Tcp'
      sourceAddressPrefix: managementPublicIp
      sourcePortRange: '*'
      destinationAddressPrefix: '*'
      destinationPortRange: '22'
      access: 'Allow'
      priority: 200
      direction: 'Inbound'
    }
  }
  denyAll
] : tierType == 'app' ? [
  {
    name: 'AllowWebToApp'
    properties: {
      protocol: 'Tcp'
      sourceAddressPrefix: webSubnetPrefix
      sourcePortRange: '*'
      destinationAddressPrefix: '*'
      destinationPortRange: '8080'
      access: 'Allow'
      priority: 100
      direction: 'Inbound'
    }
  }
  {
    name: 'AllowMgmt'
    properties: {
      protocol: 'Tcp'
      sourceAddressPrefix: managementPublicIp
      sourcePortRange: '*'
      destinationAddressPrefix: '*'
      destinationPortRange: '22'
      access: 'Allow'
      priority: 200
      direction: 'Inbound'
    }
  }
  {
    name: 'AllowVPN'
    properties: {
      protocol: '*'
      sourceAddressPrefix: vpnClientPool
      sourcePortRange: '*'
      destinationAddressPrefix: '*'
      destinationPortRange: '*'
      access: 'Allow'
      priority: 300
      direction: 'Inbound'
    }
  }
  denyAll
] : tierType == 'database' ? [
  {
    name: 'AllowAppToDb'
    properties: {
      protocol: 'Tcp'
      sourceAddressPrefix: appSubnetPrefix
      sourcePortRange: '*'
      destinationAddressPrefix: '*'
      destinationPortRange: '1433'
      access: 'Allow'
      priority: 100
      direction: 'Inbound'
    }
  }
  {
    name: 'AllowSpokeToDb'
    properties: {
      protocol: 'Tcp'
      sourceAddressPrefix: secondaryVnetPrefix
      sourcePortRange: '*'
      destinationAddressPrefix: '*'
      destinationPortRange: '1433'
      access: 'Allow'
      priority: 110
      direction: 'Inbound'
    }
  }
  {
    name: 'AllowVPNMgmt'
    properties: {
      protocol: 'Tcp'
      sourceAddressPrefix: vpnClientPool
      sourcePortRange: '*'
      destinationAddressPrefix: '*'
      destinationPortRange: '22'
      access: 'Allow'
      priority: 300
      direction: 'Inbound'
    }
  }
  denyAll
] : [
  {
    name: 'AllowHubInbound'
    properties: {
      protocol: '*'
      sourceAddressPrefix: primaryVnetPrefix
      sourcePortRange: '*'
      destinationAddressPrefix: '*'
      destinationPortRange: '*'
      access: 'Allow'
      priority: 100
      direction: 'Inbound'
    }
  }
  {
    name: 'AllowMgmt'
    properties: {
      protocol: 'Tcp'
      sourceAddressPrefix: managementPublicIp
      sourcePortRange: '*'
      destinationAddressPrefix: '*'
      destinationPortRange: '22'
      access: 'Allow'
      priority: 200
      direction: 'Inbound'
    }
  }
  denyAll
]

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    securityRules: rules
  }
}


output nsgId string = nsg.id
