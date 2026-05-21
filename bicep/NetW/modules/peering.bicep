param vnet1Id string
param vnet2Id string
param allowGatewayTransit bool

resource vnet1 'Microsoft.Network/virtualNetworks@2023-09-01' existing = {
  name: last(split(vnet1Id, '/'))
}

resource peer1to2 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  parent: vnet1
  name: 'peer-hub-to-spoke'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: allowGatewayTransit
    useRemoteGateways: false
    remoteVirtualNetwork: { id: vnet2Id }
  }
}

resource vnet2 'Microsoft.Network/virtualNetworks@2023-09-01' existing = {
  name: last(split(vnet2Id, '/'))
}

resource peer2to1 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  parent: vnet2
  name: 'peer-spoke-to-hub'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: allowGatewayTransit // Spoke uses Hub's VPN Gateway
    remoteVirtualNetwork: { id: vnet1Id }
  }
}
