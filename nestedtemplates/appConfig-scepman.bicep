@description('URL of the Storage Account\'s table endpoint to retrieve certificate information from')
param StorageAccountTableUrl string

@description('Name of SCEPman\'s app service')
param appServiceName string

@description('Base URL of SCEPman')
param scepManBaseURL string

@description('URL of the key vault')
param keyVaultURL string

@description('Name of company or organization for certificate subject')
param OrgName string

@description('When generating the SCEPman CA certificate, which kind of key pair shall be created? RSA is a software-protected RSA key; RSA-HSM is HSM-protected.')
@allowed([
  'RSA'
  'RSA-HSM'
])
param caKeyType string = 'RSA-HSM'

@description('When generating the SCEPman CA certificate, what length in bits shall the key have? Plausible values for RSA are 2048 or 4096. The size also has an impact on the Azure Key Vault pricing.')
param caKeySize int = 4096

@description('Log Analytics Workspace ID')
param logAnalyticsWorkspaceId string

@description('Log Analytics Workspace name')
param logAnalyticsWorkspaceName string

@description('License Key for SCEPman')
param license string = 'trial'

@description('The full URI where SCEPman artifact binaries are stored')
param WebsiteArtifactsUri string

@description('Use Linux App Service Plan')
param deployOnLinux bool

// Function to convert colon-style variable names to underscore-separated variable names if deployOnLinux is true
func convertVariableNameToLinux(variableName string, deployOnLinux bool) string => deployOnLinux ? replace(variableName, ':', '__') : variableName

resource appServiceName_appsettings 'Microsoft.Web/sites/config@2024-04-01' = {
  name: '${appServiceName}/appsettings'
  properties: {
    WEBSITE_RUN_FROM_PACKAGE: WebsiteArtifactsUri
    '${convertVariableNameToLinux('AppConfig:BaseUrl', deployOnLinux)}': scepManBaseURL
    '${convertVariableNameToLinux('AppConfig:LicenseKey', deployOnLinux)}': license
    '${convertVariableNameToLinux('AppConfig:AuthConfig:TenantId', deployOnLinux)}': subscription().tenantId
    '${convertVariableNameToLinux('AppConfig:UseRequestedKeyUsages', deployOnLinux)}': 'true'
    '${convertVariableNameToLinux('AppConfig:ValidityPeriodDays', deployOnLinux)}': '730'
    '${convertVariableNameToLinux('AppConfig:IntuneValidation:ValidityPeriodDays', deployOnLinux)}': '365'
    '${convertVariableNameToLinux('AppConfig:DirectCSRValidation:Enabled', deployOnLinux)}': 'true'
    '${convertVariableNameToLinux('AppConfig:IntuneValidation:DeviceDirectory', deployOnLinux)}': 'AADAndIntune'
    '${convertVariableNameToLinux('AppConfig:CRL:Source', deployOnLinux)}': 'Storage'
    '${convertVariableNameToLinux('AppConfig:EnableCertificateStorage', deployOnLinux)}': 'true'
    '${convertVariableNameToLinux('AppConfig:LoggingConfig:WorkspaceId', deployOnLinux)}': logAnalyticsWorkspaceId
    '${convertVariableNameToLinux('AppConfig:LoggingConfig:SharedKey', deployOnLinux)}': listKeys(
      resourceId('Microsoft.OperationalInsights/workspaces', logAnalyticsWorkspaceName),
      '2022-10-01'
    ).primarySharedKey
    '${convertVariableNameToLinux('AppConfig:KeyVaultConfig:KeyVaultURL', deployOnLinux)}': keyVaultURL
    '${convertVariableNameToLinux('AppConfig:CertificateStorage:TableStorageEndpoint', deployOnLinux)}': StorageAccountTableUrl
    '${convertVariableNameToLinux('AppConfig:KeyVaultConfig:RootCertificateConfig:CertificateName', deployOnLinux)}': 'SCEPman-Root-CA-V1'
    '${convertVariableNameToLinux('AppConfig:KeyVaultConfig:RootCertificateConfig:KeyType', deployOnLinux)}': caKeyType
    '${convertVariableNameToLinux('AppConfig:KeyVaultConfig:RootCertificateConfig:KeySize', deployOnLinux)}': caKeySize
    '${convertVariableNameToLinux('AppConfig:ValidityClockSkewMinutes', deployOnLinux)}': '1440'
    '${convertVariableNameToLinux('AppConfig:KeyVaultConfig:RootCertificateConfig:Subject', deployOnLinux)}': 'CN=SCEPman-Root-CA-V1, OU=${subscription().tenantId}, O="${OrgName}"'
  }
}
