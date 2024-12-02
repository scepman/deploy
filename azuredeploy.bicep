@description('Name of the Company or Organization used for the Certificate Subject')
@minLength(2)
param OrgName string

@description('License Key for SCEPman')
param license string = 'trial'

@description('Specifies the name of the Azure Key Vault. The name of a Key Vault must be globally unique and contain only DNS-compatible characters (letters, numbers, and hyphens).')
@minLength(3)
@maxLength(24)
param keyVaultName string = 'kv-scepman-UNIQUENAME'

@description('When generating the SCEPman CA certificate, which kind of key pair shall be created? RSA is a software-protected RSA key; RSA-HSM is HSM-protected.')
@allowed([
  'RSA'
  'RSA-HSM'
])
param caKeyType string = 'RSA-HSM'

@description('Choose a globally unique name for your storage account. Storage account names must be between 3 and 24 characters in length and may contain numbers and lowercase letters only.')
@minLength(3)
@maxLength(24)
param storageAccountName string = 'stscepmanuniquename'

@maxLength(40)
param appServicePlanName string = 'asp-scepman-UNIQUENAME'

@description('Provide the Resource ID of an existing App Service Plan (the long string displayed in the properties tab). Keep default value \'none\' if you want to create a new one.')
param existingAppServicePlanID string = 'none'

@description('The SCEPman App Service and part of the default FQDN. Therefore, it must be globally unique and contain only DNS-compatible characters.')
@maxLength(60)
param primaryAppServiceName string = 'app-scepman-UNIQUENAME'

@description('The Log Analytics Workspace with log data. Alphanumerics and hyphens are allowed.')
@minLength(4)
@maxLength(63)
param logAnalyticsWorkspaceName string = 'log-scepman-UNIQUENAME'

@description('The App Service for the component SCEPman Certificate Master. As it is part of the default FQDN, it must be globally unique and contain only DNS-compatible characters.')
@maxLength(60)
param certificateMasterAppServiceName string = 'app-scepman-UNIQUENAME-cm'

@description('Choose \'true\' to deploy SCEPman with a Virtual Network. In this case, you must also provide names for the parameters virtualNetworkName, privateEndpointForTableStorage, and privateEndpointForKeyVaultName.')
param deployPrivateNetwork bool = true

@description('The name of the Virtual Network. This is only applicable if deployPrivateNetwork is chosen.')
@maxLength(80)
param virtualNetworkName string = 'vnet-scepman-UNIQUENAME'

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

var artifactsRepositoryUrl = 'https://raw.githubusercontent.com/scepman/install/master/'
var ArtifactsLocationSCEPman = uri(artifactsRepositoryUrl, 'dist/Artifacts.zip')
var ArtifactsLocationCertMaster = uri(artifactsRepositoryUrl, 'dist-certmaster/CertMaster-Artifacts.zip')
var appServiceNames = [
  primaryAppServiceName
  certificateMasterAppServiceName
]

module pid_a262352f_52a9_4ed9_a9ba_6a2b2478d19b_partnercenter './nested_pid_a262352f_52a9_4ed9_a9ba_6a2b2478d19b_partnercenter.bicep' = {
  name: 'pid-a262352f-52a9-4ed9-a9ba-6a2b2478d19b-partnercenter'
  params: {}
}

module CreateVirtualNetwork 'nestedtemplates/vnet.json' = if (deployPrivateNetwork) {
  name: 'CreateVirtualNetwork'
  params: {
    virtualNetworkName: virtualNetworkName
    location: location
    resourceTags: resourceTags
  }
}

@batchSize(1)
module AppService_ConnectionToVirtualNetwork 'nestedtemplates/vnet-to-appservices.json' = [
  for i in range(0, 2): {
    name: 'AppService-${i}-ConnectionToVirtualNetwork'
    params: {
      virtualNetworkName: virtualNetworkName
      location: location
      appServiceName: appServiceNames[i]
    }
    dependsOn: [
      CreateVirtualNetwork
      SCEPmanAppServices
    ]
  }
]

module SCEPmanAppServices 'nestedtemplates/appSvcDouble.json' = {
  name: 'SCEPmanAppServices'
  params: {
    AppServicePlanName: appServicePlanName
    existingAppServicePlanID: existingAppServicePlanID
    appServiceName: primaryAppServiceName
    appServiceName2: certificateMasterAppServiceName
    location: location
    resourceTags: resourceTags
  }
}

module AzureMonitor 'nestedtemplates/loganalytics.json' = {
  name: 'AzureMonitor'
  params: {
    logAnalyticsAccountName: logAnalyticsWorkspaceName
    location: location
    resourceTags: resourceTags
  }
}

module SCEPmanVault 'nestedtemplates/vault.json' = {
  name: 'SCEPmanVault'
  params: {
    keyVaultName: keyVaultName
    permittedPrincipalId: SCEPmanAppServices.outputs.scepmanPrincipalID
    location: location
    resourceTags: resourceTags
    virtualNetworkName: virtualNetworkName
    privateEndpointName: (deployPrivateNetwork ? privateEndpointForKeyVaultName : 'None')
  }
  dependsOn: [
    CreateVirtualNetwork
    AppService_ConnectionToVirtualNetwork
    SCEPmanStorageAccount
  ]
}

module DeploymentSCEPmanConfig 'nestedtemplates/appConfig-scepman.json' = {
  name: 'DeploymentSCEPmanConfig'
  params: {
    StorageAccountTableUrl: SCEPmanStorageAccount.outputs.storageAccountTableUrl
    appServiceName: primaryAppServiceName
    scepManBaseURL: SCEPmanAppServices.outputs.scepmanURL
    keyVaultURL: SCEPmanVault.outputs.keyVaultURL
    caKeyType: caKeyType
    logAnalyticsWorkspaceId: AzureMonitor.outputs.workspaceId
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    OrgName: OrgName
    WebsiteArtifactsUri: ArtifactsLocationSCEPman
    license: license
  }
}

module DeploymentCertMasterConfig 'nestedtemplates/appConfig-certmaster.json' = {
  name: 'DeploymentCertMasterConfig'
  params: {
    appServiceName: certificateMasterAppServiceName
    scepmanUrl: SCEPmanAppServices.outputs.scepmanURL
    StorageAccountTableUrl: SCEPmanStorageAccount.outputs.storageAccountTableUrl
    logAnalyticsWorkspaceId: AzureMonitor.outputs.workspaceId
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    WebsiteArtifactsUri: ArtifactsLocationCertMaster
  }
}

module SCEPmanStorageAccount 'nestedtemplates/stgAccount.json' = {
  name: 'SCEPmanStorageAccount'
  params: {
    StorageAccountName: storageAccountName
    location: location
    resourceTags: resourceTags
    tableContributorPrincipals: [
      SCEPmanAppServices.outputs.scepmanPrincipalID
      SCEPmanAppServices.outputs.certmasterPrincipalID
    ]
    virtualNetworkName: virtualNetworkName
    privateEndpointName: (deployPrivateNetwork ? privateEndpointForTableStorage : 'None')
  }
  dependsOn: [
    CreateVirtualNetwork
    AppService_ConnectionToVirtualNetwork
  ]
}
