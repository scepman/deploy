@description('URL of the Storage Account\'s table endpoint to store certificate information')
param StorageAccountTableUrl string

@description('The full URI where CertMaster artifact binaries are stored')
param WebsiteArtifactsUri string

@description('Name of Certificate Master\'s app service')
param appServiceName string

@description('The URL of the SCEPman App Service')
param scepmanUrl string

@description('Log Analytics Workspace ID')
param logAnalyticsWorkspaceId string

@description('Log Analytics Workspace name')
param logAnalyticsWorkspaceName string

resource appServiceName_appsettings 'Microsoft.Web/sites/config@2022-09-01' = {
  name: '${appServiceName}/appsettings'
  properties: {
    WEBSITE_RUN_FROM_PACKAGE: WebsiteArtifactsUri
    'AppConfig:AzureStorage:TableStorageEndpoint': StorageAccountTableUrl
    'AppConfig:SCEPman:URL': scepmanUrl
    'AppConfig:AuthConfig:TenantId': subscription().tenantId
    'AppConfig:LoggingConfig:WorkspaceId': logAnalyticsWorkspaceId
    'AppConfig:LoggingConfig:SharedKey': listKeys(
      resourceId('Microsoft.OperationalInsights/workspaces', logAnalyticsWorkspaceName),
      '2022-10-01'
    ).primarySharedKey
  }
}
