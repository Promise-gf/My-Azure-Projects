param name string
param location string
param targetResourceId string
param groupId string
param subnetId string
param vnetIds array
param dnsZoneName string
param targetResourceName string
param tags object = {}

resource dnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: dnsZoneName
  location: 'global'
  tags: tags
}

resource dnsLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [
  for id in vnetIds: {
    name: 'link-${uniqueString(id)}'
    parent: dnsZone
    location: 'global'
    properties: {
      registrationEnabled: false
      virtualNetwork: {
        id: id
      }
    }
  }
]

resource pe 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'pec-${name}'
        properties: {
          privateLinkServiceId: targetResourceId
          groupIds: [
            groupId
          ]
        }
      }
    ]
  }
}

resource dnsARecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  name: targetResourceName
  parent: dnsZone
  properties: {
    ttl: 300
    aRecords: [
      {
        ipv4Address: pe.properties.customDnsConfigs[0].ipAddresses[0]
      }
    ]
  }
}

output peId string = pe.id
