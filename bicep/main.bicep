targetScope = 'resourceGroup'

param location string = resourceGroup().location
param tags object = { development: 'true' }
param prefix string = 'dev'

@description('The admin UserName for the VM')
param adminUsername string

@description('The admin Password for the VM')
@secure()
param adminPassword string

@description('Resource ID for Log Analytics Workspace')
param logAnalyticsWorkspaceId string

@description('Resource ID for Data Collection Rule')
param dataCollectionRuleId string = ''

@description('Auto-ShutDown time in 24hr format, e.g. 1900 for 10 PM')
param autoShutDownTime string = '1900'

@description('Set to true to use existing network resources, false to create new ones')
param createNewNetwork bool = true

@description('Resource ID for existing Subnet (required if createNewNetwork is false)')
param existingSubnetId string = ''

@description('Required if createNewNetwork is true Vnet address space')
param vnetAddressSpace string = '10.0.0.0/16'

@description('Array of VMs to deploy')
param VmConfigs array = [
  {
    name: 'win-01'
    osType: 'Windows'
    vmSize: 'Standard_D2s_v3'
    script: 'powershell.exe -Command "Write-Host Windows Setup Done | Out-File C:\\setup.txt"'
    sshPublicKey: ''
  }
  {
    name: 'linux-01'
    osType: 'Linux'
    vmSize: 'Standard_D2s_v3'
    script: 'echo "Linux Setup Done" > /tmp/setup.txt'
    sshPublicKey: ''
  }
]

// VARIABLES
var computeSubnetPrefix = cidrSubnet(vnetAddressSpace, 24, 1)
var bastionSubnetPrefix = cidrSubnet(vnetAddressSpace, 26, 0)
var vaultName = 'rsv-${uniqueString(resourceGroup().id)}'
var existingSubnetIdResolved = !createNewNetwork && empty(existingSubnetId)
  ? 'Error: existingSubnetId is required when createNewNetwork is false ***'
  : existingSubnetId
var targetSubnetId = createNewNetwork
  ? resourceId('Microsoft.Network/virtualNetworks/subnets', '${prefix}-vnet', 'compute-subnet')
  : existingSubnetIdResolved

// ===========================================================================
// NETWORKING
// ===========================================================================

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-05-01' = if (createNewNetwork) {
  name: '${prefix}-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-Bastion-RDP'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-Bastion-SSH'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
      {
        name: 'Deny-All-Inbound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 4096
          direction: 'Inbound'
        }
      }
    ]
  }
}

resource nsgDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (createNewNetwork) {
  name: 'nsgToLogAnalytics'
  scope: nsg
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      { category: 'NetworkSecurityGroupEvent', enabled: true }
      { category: 'NetworkSecurityGroupRuleCounter', enabled: true }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = if (createNewNetwork) {
  name: '${prefix}-vnet'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [vnetAddressSpace]
    }
  }
}

resource computeSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-05-01' = if (createNewNetwork) {
  parent: vnet
  name: 'compute-subnet'
  properties: {
    addressPrefix: computeSubnetPrefix
    networkSecurityGroup: { id: nsg.id }
  }
}

resource bastionSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-05-01' = if (createNewNetwork) {
  parent: vnet
  name: 'AzureBastionSubnet'
  properties: {
    addressPrefix: bastionSubnetPrefix
  }
}

resource bastionPip 'Microsoft.Network/publicIPAddresses@2023-05-01' = if (createNewNetwork) {
  name: '${prefix}-bastion-pip'
  location: location
  tags: tags
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

resource bastionHost 'Microsoft.Network/bastionHosts@2023-05-01' = if (createNewNetwork) {
  name: '${prefix}-bastionHost'
  location: location
  tags: tags
  sku: { name: 'Standard' }
  properties: {
    ipConfigurations: [
      {
        name: 'bastionIpConfig'
        properties: {
          subnet: { id: bastionSubnet.id }
          publicIPAddress: { id: bastionPip.id }
        }
      }
    ]
    enableTunneling: true
  }
}

// ===========================================================================
// INFRASTRUCTURE
// ===========================================================================

resource avsetWindows 'Microsoft.Compute/availabilitySets@2024-03-01' = {
  name: '${prefix}-avset-win'
  location: location
  tags: tags
  sku: { name: 'Aligned' }
  properties: {
    platformFaultDomainCount: 2
    platformUpdateDomainCount: 5
  }
}

resource avsetLinux 'Microsoft.Compute/availabilitySets@2024-03-01' = {
  name: '${prefix}-avset-linux'
  location: location
  tags: tags
  sku: { name: 'Aligned' }
  properties: {
    platformFaultDomainCount: 2
    platformUpdateDomainCount: 5
  }
}

resource vault 'Microsoft.RecoveryServices/vaults@2023-04-01' = {
  name: vaultName
  location: location
  tags: tags
  sku: { name: 'Standard', tier: 'Standard' }
  properties: {
    // Enabled to allow backup registration without a Private Endpoint. 
    // Recommend hardening to 'Disabled' post-deployment if possible.
    publicNetworkAccess: 'Enabled'
  }
}

// Enhanced V2 policy is required for Trusted Launch / Gen2 VMs
resource policy 'Microsoft.RecoveryServices/vaults/backupPolicies@2023-04-01' = {
  name: 'DailyBackupPolicy-${prefix}'
  parent: vault
  properties: {
    policyType: 'V2'
    backupManagementType: 'AzureIaasVM'
    instantRpRetentionRangeInDays: 2
    schedulePolicy: {
      schedulePolicyType: 'SimpleSchedulePolicyV2'
      scheduleRunFrequency: 'Daily'
      dailySchedule: {
        scheduleRunTimes: ['2000-01-01T02:00:00Z']
      }
    }
    retentionPolicy: {
      retentionPolicyType: 'LongTermRetentionPolicy'
      dailySchedule: {
        retentionTimes: ['2000-01-01T02:00:00Z']
        retentionDuration: { count: 30, durationType: 'Days' }
      }
    }
    timeZone: 'UTC'
  }
}

// ===========================================================================
// VM LOOP
// ===========================================================================

// Explicit dependsOn is required here because targetSubnetId uses resourceId() 
// which breaks Bicep's implicit dependency graph.
resource nicLoop 'Microsoft.Network/networkInterfaces@2023-05-01' = [
  for vm in VmConfigs: {
    name: '${vm.name}-nic'
    location: location
    tags: tags
    dependsOn: createNewNetwork ? [computeSubnet] : []
    properties: {
      ipConfigurations: [
        {
          name: 'ipconfig1'
          properties: {
            privateIPAllocationMethod: 'Dynamic'
            subnet: { id: targetSubnetId }
          }
        }
      ]
    }
  }
]

resource vmLoop 'Microsoft.Compute/virtualMachines@2024-03-01' = [
  for (vm, index) in VmConfigs: {
    name: vm.name
    location: location
    tags: tags
    identity: { type: 'SystemAssigned' }
    properties: {
      hardwareProfile: { vmSize: vm.vmSize }
      availabilitySet: { id: vm.osType == 'Windows' ? avsetWindows.id : avsetLinux.id }
      osProfile: {
        computerName: vm.name
        adminUsername: adminUsername
        adminPassword: adminPassword
        windowsConfiguration: vm.osType == 'Windows'
          ? {
              enableAutomaticUpdates: true
              patchSettings: {
                assessmentMode: 'AutomaticByPlatform'
                patchMode: 'AutomaticByPlatform'
              }
            }
          : null
        linuxConfiguration: vm.osType == 'Linux'
          ? {
              disablePasswordAuthentication: !empty(vm.sshPublicKey)
              ssh: !empty(vm.sshPublicKey)
                ? {
                    publicKeys: [
                      {
                        path: '/home/${adminUsername}/.ssh/authorized_keys'
                        keyData: vm.sshPublicKey
                      }
                    ]
                  }
                : null
            }
          : null
      }
      storageProfile: {
        osDisk: {
          name: '${vm.name}-osdisk'
          createOption: 'FromImage'
          managedDisk: { storageAccountType: 'Premium_LRS' }
          deleteOption: 'Delete'
        }
        imageReference: vm.osType == 'Windows'
          ? {
              publisher: 'MicrosoftWindowsServer'
              offer: 'WindowsServer'
              sku: '2022-Datacenter-g2'
              version: 'latest'
            }
          : {
              publisher: 'Canonical'
              offer: '0001-com-ubuntu-server-jammy'
              sku: '22_04-lts-gen2'
              version: 'latest'
            }
      }
      networkProfile: {
        networkInterfaces: [
          {
            id: nicLoop[index].id
            properties: { deleteOption: 'Delete' }
          }
        ]
      }
      securityProfile: {
        securityType: 'TrustedLaunch'
        uefiSettings: { secureBootEnabled: true, vTpmEnabled: true }
      }
    }
  }
]

// ===========================================================================
// EXTENSIONS & BACKUP
// ===========================================================================

resource extAma 'Microsoft.Compute/virtualMachines/extensions@2024-03-01' = [
  for (vm, index) in VmConfigs: {
    parent: vmLoop[index]
    name: vm.osType == 'Windows' ? 'AzureMonitorWindowsAgent' : 'AzureMonitorLinuxAgent'
    location: location
    properties: {
      publisher: 'Microsoft.Azure.Monitor'
      type: vm.osType == 'Windows' ? 'AzureMonitorWindowsAgent' : 'AzureMonitorLinuxAgent'
      typeHandlerVersion: vm.osType == 'Windows' ? '1.22' : '1.29'
      autoUpgradeMinorVersion: true
      settings: {}
    }
  }
]

resource dcrAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = [
  for (vm, index) in VmConfigs: if (!empty(dataCollectionRuleId)) {
    name: 'dcr-association-${vm.name}'
    scope: vmLoop[index]
    properties: {
      dataCollectionRuleId: dataCollectionRuleId
      description: 'Association for ${vm.name} VM Monitoring'
    }
  }
]

resource customScriptExt 'Microsoft.Compute/virtualMachines/extensions@2023-03-01' = [
  for (vm, index) in VmConfigs: {
    parent: vmLoop[index]
    name: vm.osType == 'Windows' ? 'CustomScriptExtension' : 'customScript'
    location: location
    dependsOn: [extAma[index]]
    properties: {
      publisher: vm.osType == 'Windows' ? 'Microsoft.Compute' : 'Microsoft.Azure.Extensions'
      type: vm.osType == 'Windows' ? 'CustomScriptExtension' : 'customScript'
      typeHandlerVersion: vm.osType == 'Windows' ? '1.10' : '2.1'
      settings: { commandToExecute: vm.script }
    }
  }
]

resource autoShutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = [
  for (vm, index) in VmConfigs: {
    name: 'shutdown-computevm-${vm.name}'
    location: location
    tags: tags
    properties: {
      status: 'Enabled'
      taskType: 'ComputeVmShutdownTask'
      dailyRecurrence: { time: autoShutDownTime }
      timeZoneId: 'UTC'
      targetResourceId: vmLoop[index].id
      notificationSettings: { status: 'Disabled' }
    }
  }
]

// Path uses 'iaasvmcontainerv2' (v2) specifically for Gen2/TrustedLaunch VMs.
// 'IaasVMContainer;' prefix is required by the ARM API.
resource backupInstance 'Microsoft.RecoveryServices/vaults/backupFabrics/protectionContainers/protectedItems@2023-04-01' = [
  for (vm, index) in VmConfigs: {
    name: '${vault.name}/Azure/IaasVMContainer;iaasvmcontainerv2;${resourceGroup().name};${vm.name}/vm;iaasvmcontainerv2;${resourceGroup().name};${vm.name}'
    location: location
    properties: {
      protectedItemType: 'Microsoft.Compute/virtualMachines'
      sourceResourceId: vmLoop[index].id
      policyId: policy.id
    }
  }
]

// ===========================================================================
// OUTPUTS
// ===========================================================================

// Commented out due to Bicep compiler limitation with resource arrays in outputs.
// output vmResourceIds array = [for (vm, index) in vmLoop: vm.id]

output bastionHostName string = createNewNetwork ? bastionHost.name : 'N/A - using existing network resources'

output monitoringWarning string = empty(dataCollectionRuleId)
  ? 'Warning: No Data Collection Rule ID provided.'
  : 'VMs will be associated with the provided Data Collection Rule.'

output linuxAuthWarning string = !empty(filter(VmConfigs, vm => vm.osType == 'Linux' && empty(vm.sshPublicKey)))
  ? 'Warning: Linux VM missing SSH key.'
  : 'All Linux VMs have SSH public keys provided.'
