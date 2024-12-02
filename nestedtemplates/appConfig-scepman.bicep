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

resource appServiceName_appsettings 'Microsoft.Web/sites/config@2022-09-01' = {
  name: '${appServiceName}/appsettings'
  properties: {
    WEBSITE_RUN_FROM_PACKAGE: WebsiteArtifactsUri
    'AppConfig:BaseUrl': scepManBaseURL
    'AppConfig:LicenseKey': license
    'AppConfig:AuthConfig:TenantId': subscription().tenantId
    'AppConfig:UseRequestedKeyUsages': 'true'
    'AppConfig:ValidityPeriodDays': '730'
    'AppConfig:IntuneValidation:ValidityPeriodDays': '365'
    'AppConfig:DirectCSRValidation:Enabled': 'true'
    'AppConfig:IntuneValidation:DeviceDirectory': 'AADAndIntune'
    'AppConfig:CRL:Source': 'Storage'
    'AppConfig:EnableCertificateStorage': 'true'
    'AppConfig:LoggingConfig:WorkspaceId': logAnalyticsWorkspaceId
    'AppConfig:LoggingConfig:SharedKey': listKeys(
      resourceId('Microsoft.OperationalInsights/workspaces', logAnalyticsWorkspaceName),
      '2022-10-01'
    ).primarySharedKey
    'AppConfig:KeyVaultConfig:KeyVaultURL': keyVaultURL
    'AppConfig:CertificateStorage:TableStorageEndpoint': StorageAccountTableUrl
    'AppConfig:KeyVaultConfig:RootCertificateConfig:CertificateName': 'SCEPman-Root-CA-V1'
    'AppConfig:KeyVaultConfig:RootCertificateConfig:KeyType': caKeyType
    'AppConfig:KeyVaultConfig:RootCertificateConfig:KeySize': caKeySize
    'AppConfig:ValidityClockSkewMinutes': '1440'
    'AppConfig:KeyVaultConfig:RootCertificateConfig:Subject': 'CN=SCEPman-Root-CA-V1, OU=${subscription().tenantId}, O="${OrgName}"'
  }
}
