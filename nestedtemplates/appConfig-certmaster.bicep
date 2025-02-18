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

@description('Use Linux App Service Plan')
param deployOnLinux bool

// Function to convert colon-style variable names to underscore-separated variable names if deployOnLinux is true
func convertVariableNameToLinux(variableName string, deployOnLinux bool) string => deployOnLinux ? replace(variableName, ':', '__') : variableName

resource appServiceName_appsettings 'Microsoft.Web/sites/config@2024-04-01' = {
  name: '${appServiceName}/appsettings'
  properties: {
    WEBSITE_RUN_FROM_PACKAGE: WebsiteArtifactsUri
    '${convertVariableNameToLinux('AppConfig:AzureStorage:TableStorageEndpoint', deployOnLinux)}': StorageAccountTableUrl
    '${convertVariableNameToLinux('AppConfig:SCEPman:URL', deployOnLinux)}': scepmanUrl
    '${convertVariableNameToLinux('AppConfig:AuthConfig:TenantId', deployOnLinux)}': subscription().tenantId
    '${convertVariableNameToLinux('AppConfig:LoggingConfig:WorkspaceId', deployOnLinux)}': logAnalyticsWorkspaceId
    '${convertVariableNameToLinux('AppConfig:LoggingConfig:SharedKey', deployOnLinux)}': listKeys(
      resourceId('Microsoft.OperationalInsights/workspaces', logAnalyticsWorkspaceName),
      '2022-10-01'
    ).primarySharedKey
    '${convertVariableNameToLinux('AppConfig:LoggingConfig:AzureOfferingDomain', deployOnLinux)}': 'azure.us'
    '${convertVariableNameToLinux('AppConfig:AzureCloudConfig:AzureADEndpoint', deployOnLinux)}': 'https://login.microsoftonline.us'
    '${convertVariableNameToLinux('AppConfig:AzureCloudConfig:MSGraphEndpoint', deployOnLinux)}': 'https://graph.microsoft.us'
    '${convertVariableNameToLinux('AppConfig:AzureCloudConfig:KeyVaultEndpoint', deployOnLinux)}': 'https://vault.usgovcloudapi.net'
    '${convertVariableNameToLinux('AppConfig:AzureCloudConfig:ManagementEndpoint', deployOnLinux)}': 'https://api.manage.microsoft.us'
  }
}
