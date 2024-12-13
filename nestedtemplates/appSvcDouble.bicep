@description('Provide the AppServicePlan ID of an existing App Service Plan. Keep default value \'none\' if you want to create a new one.')
param existingAppServicePlanID string = 'none'

@description('Name of the App Service Plan to be created')
param AppServicePlanName string

@description('Name of App Service to be created')
param appServiceName string

@description('Name of second App Service to be created')
param appServiceName2 string

@description('Use Linux App Service Plan')
param deployOnLinux bool

@description('Resource Group')
param location string

@description('Tags to be assigned to the created resources')
param resourceTags object

resource AppServicePlan 'Microsoft.Web/serverfarms@2024-04-01' = if (existingAppServicePlanID == 'none') {
  name: AppServicePlanName
  location: location
  sku: {
    tier: 'Standard'
    name: 'S1'
  }
  kind: deployOnLinux ? 'app,linux' : 'app'
  tags: resourceTags
  properties: {
    targetWorkerCount: 1
  }
}

resource appService 'Microsoft.Web/sites@2024-04-01' = {
  name: appServiceName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  tags: resourceTags
  properties: {
    serverFarmId: ((existingAppServicePlanID == 'none') ? AppServicePlan.id : existingAppServicePlanID)
    clientAffinityEnabled: false
    httpsOnly: false
    clientCertEnabled: true
    clientCertMode: 'OptionalInteractiveUser'
    siteConfig: {
      alwaysOn: true
      http20Enabled: false
      ftpsState: 'Disabled'
      use32BitWorkerProcess: false
    }
  }
}

resource appService2 'Microsoft.Web/sites@2024-04-01' = {
  name: appServiceName2
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  tags: resourceTags
  properties: {
    serverFarmId: ((existingAppServicePlanID == 'none') ? AppServicePlan.id : existingAppServicePlanID)
    clientAffinityEnabled: true
    httpsOnly: true
    siteConfig: {
      alwaysOn: true
      http20Enabled: true
      ftpsState: 'Disabled'
      use32BitWorkerProcess: false
      minTlsVersion: '1.3'
    }
  }
}

output scepmanURL string = uri('https://${appService.properties.defaultHostName}', '/')
output scepmanPrincipalID string = reference(appServiceName, '2022-03-01', 'Full').identity.principalId
output certmasterPrincipalID string = reference(appServiceName2, '2022-03-01', 'Full').identity.principalId
output appServicePlanID string = ((existingAppServicePlanID == 'none') ? AppServicePlan.id : existingAppServicePlanID)
