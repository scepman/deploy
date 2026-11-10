@description('Name of the Company or Organization used for the Certificate Subject')
@minLength(2)
param OrgName string

@description('License Key for SCEPman')
param license string = 'trial'

@description('Update channel of SCEPman and Certificate Master. \'prod\' is recommended for production use.')
@allowed([
  'prod'
  'beta'
  'internal'
])
param updateChannel string = 'prod'

@description('Specifies the name of the Azure Key Vault. The name of a Key Vault must be globally unique and contain only DNS-compatible characters (letters, numbers, and hyphens). Ignored if existingKeyVaultID is set.')
@minLength(3)
@maxLength(24)
param keyVaultName string = 'kv-scepman-UNIQUENAME'

@description('Provide the Resource ID of an existing Key Vault using the Azure RBAC permission model. Keep default value “none” if you want to create a new one. No private endpoint is created for an existing Key Vault.')
param existingKeyVaultID string = 'none'

@description('When generating the SCEPman CA certificate, which kind of key pair shall be created? RSA is a software-protected RSA key; RSA-HSM is HSM-protected.')
@allowed([
  'RSA'
  'RSA-HSM'
])
param caKeyType string = 'RSA-HSM'

@description('Choose a globally unique name for your storage account. Storage account names must be between 3 and 24 characters in length and may contain numbers and lowercase letters only. Ignored if existingStorageAccountID is set.')
@minLength(3)
@maxLength(24)
param storageAccountName string = 'stscepmanuniquename'

@description('Provide the Resource ID of an existing Storage Account. Keep default value “none” if you want to create a new one. No private endpoint is created for an existing Storage Account.')
param existingStorageAccountID string = 'none'

@maxLength(40)
param appServicePlanName string = 'asp-scepman-UNIQUENAME'

@description('Provide the Resource ID of an existing App Service Plan (the long string displayed in the properties tab). Keep default value “none” if you want to create a new one. The plan must be in the same subscription and region as the deployment.')
param existingAppServicePlanID string = 'none'

@description('Use Linux App Service Plan. Ignored if existingAppServicePlanID is set, as the operating system is then taken from the existing plan.')
param deployOnLinux bool = true

@description('The SCEPman App Service and part of the default FQDN. Therefore, it must be globally unique and contain only DNS-compatible characters.')
@maxLength(60)
param primaryAppServiceName string = 'app-scepman-UNIQUENAME'

@description('The Log Analytics Workspace for SCEPman’s logging. Alphanumerics and hyphens are allowed.')
@minLength(4)
@maxLength(63)
param logAnalyticsWorkspaceName string = 'log-scepman-UNIQUENAME'

@description('The App Service for the component SCEPman Certificate Master. As it is part of the default FQDN, it must be globally unique and contain only DNS-compatible characters.')
@maxLength(60)
param certificateMasterAppServiceName string = 'app-scepman-UNIQUENAME-cm'

@description('Enable the App Service health check.')
param enableHealthCheck bool = true

@description('Enable the static SCEP endpoint (/static) for third-party MDM solutions.')
param enableStaticValidation bool = false

@description('Challenge password for the static SCEP endpoint. It is stored as a Key Vault secret. Leave empty to keep an existing secret.')
@secure()
param staticValidationRequestPassword string = ''

@description('Enable the static AAD SCEP endpoint (/static/aad), e.g. for Kandji or Google Workspace. Requires SCEPman Enterprise Edition.')
param enableStaticAADValidation bool = false

@description('Challenge password for the static AAD SCEP endpoint. It is stored as a Key Vault secret. Leave empty to keep an existing secret.')
@secure()
param staticAADValidationRequestPassword string = ''

@description('Enable the Domain Controller SCEP endpoint (/dc). Requires SCEPman Enterprise Edition.')
param enableDCValidation bool = false

@description('Challenge password for the Domain Controller SCEP endpoint. It is stored as a Key Vault secret. Leave empty to keep an existing secret.')
@secure()
param dcValidationRequestPassword string = ''

@description('Enable the Jamf SCEP endpoint (/jamf).')
param enableJamfValidation bool = false

@description('URL of your Jamf Pro instance, e.g. https://example.jamfcloud.com/. Only applicable if enableJamfValidation is chosen.')
param jamfUrl string = ''

@description('Client ID of the Jamf Pro API client. Only applicable if enableJamfValidation is chosen.')
param jamfClientId string = ''

@description('Client secret of the Jamf Pro API client. It is stored as a Key Vault secret. Leave empty to keep an existing secret.')
@secure()
param jamfClientSecret string = ''

@description('Challenge password for the Jamf SCEP endpoint (max. 32 characters). It is stored as a Key Vault secret. Leave empty to keep an existing secret.')
@secure()
param jamfValidationRequestPassword string = ''

@description('Enable the Enrollment REST API (/api/csr). Requires SCEPman Enterprise Edition and app role assignments on the SCEPman-api app registration.')
param enableEnrollmentApi bool = false

@description('Allow certificate renewals via EST (simplereenroll) for certificates issued via the Enrollment REST API. Only applicable if enableEnrollmentApi is chosen.')
param enableEnrollmentApiRenewals bool = false

@description('Choose “true” to deploy SCEPman with a Virtual Network. In this case, you must also provide names for the parameters virtualNetworkName, privateEndpointForTableStorage, and privateEndpointForKeyVaultName.')
param deployPrivateNetwork bool = true

@description('The name of the Virtual Network. This is only applicable if deployPrivateNetwork is chosen.')
@maxLength(80)
param virtualNetworkName string = 'vnet-scepman-UNIQUENAME'

@description('Name of the Network Security Group applied to the subnets. This is only applicable if deployPrivateNetwork is chosen.')
@maxLength(80)
param nsgName string = 'nsg-scepman-UNIQUENAME'

@description('Name of the Private Endpoint for the Key Vault. This is only applicable if deployPrivateNetwork is chosen.')
@minLength(4)
@maxLength(64)
param privateEndpointForKeyVaultName string = 'pep-kv-scepman-UNIQUENAME'

@description('Name of the Private Endpoint for the Azure Table Storage Service. This is only applicable if deployPrivateNetwork is chosen.')
@minLength(4)
@maxLength(64)
param privateEndpointForTableStorage string = 'pep-sts-scepman-UNIQUENAME'

@description('Location for all resources. For a manual deployment, we recommend the default value.')
param location string = resourceGroup().location

@description('Tags to be assigned to all created resources. Use JSON syntax, e.g. if you want to add tags env with value dev and project with value scepman, then write { "env":"dev", "project":"scepman"}.')
param resourceTags object = {}

var useExistingAppServicePlan = existingAppServicePlanID != 'none'
var existingAppServicePlanIdSegments = split(existingAppServicePlanID, '/')
var appServicePlanSubscriptionId = useExistingAppServicePlan ? existingAppServicePlanIdSegments[2] : subscription().subscriptionId
var appServicePlanResourceGroupName = useExistingAppServicePlan ? existingAppServicePlanIdSegments[4] : resourceGroup().name

resource existingAppServicePlan 'Microsoft.Web/serverfarms@2025-03-01' existing = if (useExistingAppServicePlan) {
  scope: resourceGroup(appServicePlanSubscriptionId, appServicePlanResourceGroupName)
  name: last(existingAppServicePlanIdSegments)
}

// 'reserved' is true for Linux App Service Plans
var effectiveDeployOnLinux = useExistingAppServicePlan ? existingAppServicePlan!.properties.reserved : deployOnLinux

var useExistingKeyVault = existingKeyVaultID != 'none'
var existingKeyVaultIdSegments = split(existingKeyVaultID, '/')
var effectiveKeyVaultName = useExistingKeyVault ? last(existingKeyVaultIdSegments) : keyVaultName
var keyVaultSubscriptionId = useExistingKeyVault ? existingKeyVaultIdSegments[2] : subscription().subscriptionId
var keyVaultResourceGroupName = useExistingKeyVault ? existingKeyVaultIdSegments[4] : resourceGroup().name

var useExistingStorageAccount = existingStorageAccountID != 'none'
var existingStorageAccountIdSegments = split(existingStorageAccountID, '/')
var effectiveStorageAccountName = useExistingStorageAccount ? last(existingStorageAccountIdSegments) : storageAccountName
var storageAccountSubscriptionId = useExistingStorageAccount ? existingStorageAccountIdSegments[2] : subscription().subscriptionId
var storageAccountResourceGroupName = useExistingStorageAccount ? existingStorageAccountIdSegments[4] : resourceGroup().name

var artifactsRepositoryUrl = 'https://raw.githubusercontent.com/scepman/install/master/'
// The artifact names of the internal channel differ between Windows and Linux
var artifactsChannelSuffix = {
  prod: ''
  beta: '-Beta'
  internal: effectiveDeployOnLinux ? '-Internal' : '-Intern'
}
var artifactsPlatformSuffix = effectiveDeployOnLinux ? '-Linux' : ''
var ArtifactsLocationSCEPman = uri(artifactsRepositoryUrl, 'dist/Artifacts${artifactsPlatformSuffix}${artifactsChannelSuffix[updateChannel]}.zip')
var ArtifactsLocationCertMaster = uri(artifactsRepositoryUrl, 'dist-certmaster/CertMaster-Artifacts${artifactsPlatformSuffix}${artifactsChannelSuffix[updateChannel]}.zip')
var appServiceNames = [
  primaryAppServiceName
  certificateMasterAppServiceName
]

var scepEndpointAppSettings = union(
  enableStaticValidation ? { 'AppConfig:StaticValidation:Enabled': 'true' } : {},
  enableStaticAADValidation ? { 'AppConfig:StaticAADValidation:Enabled': 'true' } : {},
  enableDCValidation ? { 'AppConfig:DCValidation:Enabled': 'true' } : {},
  enableJamfValidation
    ? {
        'AppConfig:JamfValidation:Enabled': 'true'
        'AppConfig:JamfValidation:URL': jamfUrl
        'AppConfig:JamfValidation:ClientID': jamfClientId
      }
    : {},
  enableEnrollmentApi
    ? {
        'AppConfig:DbCSRValidation:Enabled': 'true'
        'AppConfig:DbCSRValidation:AllowRenewals': string(enableEnrollmentApiRenewals)
      }
    : {}
)

// SCEPman reads these from its Key Vault; Key Vault values take precedence over app settings
var scepEndpointSecrets = {
  'AppConfig--StaticValidation--RequestPassword': enableStaticValidation ? staticValidationRequestPassword : ''
  'AppConfig--StaticAADValidation--RequestPassword': enableStaticAADValidation ? staticAADValidationRequestPassword : ''
  'AppConfig--DCValidation--RequestPassword': enableDCValidation ? dcValidationRequestPassword : ''
  'AppConfig--JamfValidation--RequestPassword': enableJamfValidation ? jamfValidationRequestPassword : ''
  'AppConfig--JamfValidation--ClientSecret': enableJamfValidation ? jamfClientSecret : ''
}

module pid_a262352f_52a9_4ed9_a9ba_6a2b2478d19b_partnercenter './empty.bicep' = {
  name: 'pid-a262352f-52a9-4ed9-a9ba-6a2b2478d19b-partnercenter'
  params: {}
}

module CreateVirtualNetwork 'nestedtemplates/vnet.bicep' = if (deployPrivateNetwork) {
  name: 'CreateVirtualNetwork'
  params: {
    virtualNetworkName: virtualNetworkName
    location: location
    resourceTags: resourceTags
    networkSecurityGroupName: nsgName
  }
}

@batchSize(1)
module AppService_ConnectionToVirtualNetwork 'nestedtemplates/vnet-to-appservices.bicep' = [
  for (appServiceName, i) in appServiceNames: if (deployPrivateNetwork) {
    name: 'AppSvc-${take(appServiceName, 42)}-${i}-VnetConn' // App Service names can be up to 60 characters long, but the connection resource name can only be 63 characters long. Therefore, we take only the first 42 characters of the app service name to ensure we do not exceed the limit when appending other strings.
    params: {
      virtualNetworkName: virtualNetworkName
      location: location
      appServiceName: appServiceName
    }
    dependsOn: [
      CreateVirtualNetwork
      SCEPmanAppServices
    ]
  }
]

module SCEPmanAppServices 'nestedtemplates/appSvcDouble.bicep' = {
  name: 'SCEPmanAppServices'
  params: {
    AppServicePlanName: appServicePlanName
    existingAppServicePlanID: existingAppServicePlanID
    deployOnLinux: effectiveDeployOnLinux
    appServiceName: primaryAppServiceName
    appServiceName2: certificateMasterAppServiceName
    location: location
    resourceTags: resourceTags
  }
}

module AzureMonitor 'nestedtemplates/loganalytics.bicep' = {
  name: 'AzureMonitor'
  params: {
    logAnalyticsAccountName: logAnalyticsWorkspaceName
    location: location
    resourceTags: resourceTags
  }
}

module SCEPmanVault 'nestedtemplates/vault.bicep' = {
  name: 'SCEPmanVault'
  scope: resourceGroup(keyVaultSubscriptionId, keyVaultResourceGroupName)
  params: {
    keyVaultName: effectiveKeyVaultName
    useExistingKeyVault: useExistingKeyVault
    permittedPrincipalId: SCEPmanAppServices.outputs.scepmanPrincipalID
    secrets: scepEndpointSecrets
    location: location
    resourceTags: resourceTags
    virtualNetworkName: virtualNetworkName
    privateEndpointName: (deployPrivateNetwork && !useExistingKeyVault ? privateEndpointForKeyVaultName : 'None')
  }
  dependsOn: [
    CreateVirtualNetwork
    AppService_ConnectionToVirtualNetwork
    SCEPmanStorageAccount
  ]
}

// Cross-scope module outputs compile to format(); uri() keeps ARM TTK's "URIs Should Be Properly Constructed" check passing
var keyVaultURL = uri(SCEPmanVault.outputs.keyVaultURL, '/')
var storageAccountTableUrl = uri(SCEPmanStorageAccount.outputs.storageAccountTableUrl, '/')

module DeploymentSCEPmanConfig 'nestedtemplates/appConfig-scepman.bicep' = {
  name: 'DeploymentSCEPmanConfig'
  params: {
    StorageAccountTableUrl: storageAccountTableUrl
    appServiceName: primaryAppServiceName
    deployOnLinux: effectiveDeployOnLinux
    scepManBaseURL: SCEPmanAppServices.outputs.scepmanURL
    keyVaultURL: keyVaultURL
    caKeyType: caKeyType
    logAnalyticsWorkspaceId: AzureMonitor.outputs.workspaceId
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    OrgName: OrgName
    WebsiteArtifactsUri: ArtifactsLocationSCEPman
    license: license
    enableHealthCheck: enableHealthCheck
    additionalAppSettings: scepEndpointAppSettings
  }
}

module DeploymentCertMasterConfig 'nestedtemplates/appConfig-certmaster.bicep' = {
  name: 'DeploymentCertMasterConfig'
  params: {
    appServiceName: certificateMasterAppServiceName
    deployOnLinux: effectiveDeployOnLinux
    scepmanUrl: SCEPmanAppServices.outputs.scepmanURL
    StorageAccountTableUrl: storageAccountTableUrl
    logAnalyticsWorkspaceId: AzureMonitor.outputs.workspaceId
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    WebsiteArtifactsUri: ArtifactsLocationCertMaster
    enableHealthCheck: enableHealthCheck
  }
}

module SCEPmanStorageAccount 'nestedtemplates/stgAccount.bicep' = {
  name: 'SCEPmanStorageAccount'
  scope: resourceGroup(storageAccountSubscriptionId, storageAccountResourceGroupName)
  params: {
    StorageAccountName: effectiveStorageAccountName
    useExistingStorageAccount: useExistingStorageAccount
    location: location
    resourceTags: resourceTags
    tableContributorPrincipals: [
      SCEPmanAppServices.outputs.scepmanPrincipalID
      SCEPmanAppServices.outputs.certmasterPrincipalID
    ]
    virtualNetworkName: virtualNetworkName
    privateEndpointName: (deployPrivateNetwork && !useExistingStorageAccount ? privateEndpointForTableStorage : 'None')
  }
  dependsOn: [
    CreateVirtualNetwork
    AppService_ConnectionToVirtualNetwork
  ]
}
