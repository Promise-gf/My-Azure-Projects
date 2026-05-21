param name string
param publicIpName string
param location string
param gatewaySubnetId string
param vpnClientPool string
@secure()
param vpnRootCertData string
param vpnRootCertName string
param tags object = {}

resource pip 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: publicIpName
  location: location
  sku: { name: 'Basic', tier: 'Regional' }
  tags: tags
  properties: { publicIPAllocationMethod: 'Dynamic' }
}

resource gw 'Microsoft.Network/virtualNetworkGateways@2023-09-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    enableBgp: false
    sku: { name: 'VpnGw1', tier: 'VpnGw1' }
    ipConfigurations: [
      { name: 'default', properties: { privateIPAllocationMethod: 'Dynamic', publicIPAddress: { id: pip.id }, subnet: { id: gatewaySubnetId } } }
    ]
    vpnClientConfiguration: {
      vpnClientAddressPool: { addressPrefixes: [ vpnClientPool ] }
      vpnClientProtocols: [ 'OpenVPN' ]
      vpnAuthenticationTypes: [ 'Certificate' ]
      vpnClientRootCertificates: [
        { name: vpnRootCertName, properties: { publicCertData: vpnRootCertData } }
      ]
    }
  }
}

output gatewayPublicIp string = pip.properties.ipAddress
