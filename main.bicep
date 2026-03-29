resource storageAccount 'Microsoft.Storage/storageAccounts@2023-04-01' = {
  name: 'mystorageaccount'
  location: 'WestUS'
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'

  }
}

resource appServicePlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: 'myappserviceplan'
  location: 'WestUS'
  sku: {
    name: 'F1'
    tier: 'Standard'
  }
}

resource appService 'Microsoft.Web/sites@2024-04-01' = {
  name: 'myappservice'
  location: 'WestUS'
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
  }
}
