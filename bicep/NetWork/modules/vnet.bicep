param name string
param location string
param addressSpace string
param subnets object
param nsgAssignments object
param deployVpn bool
param tags object = {}

// Safely construct subnets array without nulls
var vnetSubnets = concat(
  [
    { name: 'snet-web', properties: { addressPrefix: subnets.web, networkSecurityGroup: { id: nsgAssignments['snet-web'] }, serviceEndpoints: [ { service: 'Microsoft.Storage', locations: [ location ] } ], privateEndpointNetworkPolicies: 'Disabled' } }
    { name: 'snet-app', properties: { addressPrefix: subnets.app, networkSecurityGroup: { id: nsgAssignments['snet-app'] }, serviceEndpoints: [ { service: 'Microsoft.Storage', locations: [ location ] }, { service: 'Microsoft.Sql', locations: [ location ] } ], privateEndpointNetworkPolicies: 'Disabled' } }
    { name: 'snet-db', properties: { addressPrefix: subnets.db, networkSecurityGroup: { id: nsgAssignments['snet-db'] }, serviceEndpoints: [ { service: 'Microsoft.Sql', locations: [ location ] } ], privateEndpointNetworkPolicies: 'Disabled' } }
    { name: 'snet-pe', properties: { addressPrefix: subnets.pe, privateEndpointNetworkPolicies: 'Disabled', privateLinkServiceNetworkPolicies: 'Disabled' } }
  ],
  deployVpn ? [
    { name: 'GatewaySubnet', properties: { addressPrefix: subnets.gateway } }
  ] : []
)

resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: [ addressSpace ] }
    subnets: vnetSubnets
  }
}

output vnetId string = vnet.id
output subnetIds object = {
  web: '${vnet.id}/subnets/snet-web'
  app: '${vnet.id}/subnets/snet-app'
  db: '${vnet.id}/subnets/snet-db'
  privateEndpoints: '${vnet.id}/subnets/snet-pe'
  gateway: deployVpn ? '${vnet.id}/subnets/GatewaySubnet' : ''
  workload: contains(subnets, 'workload') ? '${vnet.id}/subnets/snet-workload' : ''
}
