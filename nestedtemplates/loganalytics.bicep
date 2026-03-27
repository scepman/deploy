@description('Name of the Log Analytics Workspace')
param logAnalyticsAccountName string

@description('Location where the resources will be deployed')
param location string

@description('Tags to be assigned to the created resources')
param resourceTags object

resource logAnalyticsAccount 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsAccountName
  location: location
  tags: resourceTags
  properties: {
    retentionInDays: 30
    sku: {
      name: 'PerGB2018'
    }
  }
}

output workspaceId string = logAnalyticsAccount.properties.customerId
