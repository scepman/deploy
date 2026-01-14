@description('Name of the Company or Organization used for the Certificate Subject')
@minLength(2)
param OrgName string

@description('License Key for SCEPman')
param license string = 'trial'

@description('Which Update Channel shall SCEPman use?')
param updateChannel string = 'prod'

@description('The sasToken required to access _artifactsLocation.  When the template is deployed using the accompanying scripts, a sasToken will be automatically generated. Use the defaultValue if the staging location is not secured.')
@secure()
param _artifactsLocationSasToken string = ''

@description('The base URI where artifacts required by this template are located including a trailing "/"')
param _artifactsLocation string = deployment().properties.templateLink.uri

@description('Location for all resources. For a manual deployment, we recommend the default value.')
param location string = resourceGroup().location

@description('Tags to be assigned to all created resources. Use JSON syntax, e.g. if you want to add tags env with value dev and project with value scepman, then write { "env":"dev", "project":"scepman"}.')
param resourceTags object = {}

var artifactsRepositoryUrl = _artifactsLocation
var ArtifactsLocationSCEPman = uri(artifactsRepositoryUrl, 'dist/Artifacts${deployOnLinux ? '-Linux' : ''}.zip${_artifactsLocationSasToken}')
var ArtifactsLocationCertMaster = uri(artifactsRepositoryUrl, 'dist-certmaster/CertMaster-Artifacts${deployOnLinux ? '-Linux' : ''}.zip${_artifactsLocationSasToken}')
var AppServicePlanName = 'asp-scepman-${uniqueString(resourceGroup().id)}'
var AppServiceName = 'app-scepman-${uniqueString(resourceGroup().id)}'
var AppServiceCertMasterName = 'app-scepman-cm-${uniqueString(resourceGroup().id)}'
var keyVaultName = 'kv-scepman-${uniqueString(resourceGroup().id)}'
var caKeyType = 'RSA-HSM'
var logAnalyticsWorkspaceName = 'log-scepman-${uniqueString(resourceGroup().id)}'
var storageAccountName = 'stscepman${uniqueString(resourceGroup().id)}'
var virtualNetworkName = 'vnet-scepman-${uniqueString(resourceGroup().id)}'
var enableHealthCheck = true
var deployPrivateNetwork = true
var deployOnLinux = true
var privateEndpointForKeyVaultName = 'pep-kv-scepman-${uniqueString(resourceGroup().id)}'
var privateEndpointForTableStorage = 'pep-sts-scepman-${uniqueString(resourceGroup().id)}'
var appServiceNames = [
  AppServiceName
  AppServiceCertMasterName
]

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
  }
}

@batchSize(1)
module AppService_ConnectionToVirtualNetwork 'nestedtemplates/vnet-to-appservices.bicep' = [
  for i in range(0, 2): if (deployPrivateNetwork) {
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

module SCEPmanAppServices 'nestedtemplates/appSvcDouble.bicep' = {
  name: 'SCEPmanAppServices'
  params: {
    AppServicePlanName: AppServicePlanName
    deployOnLinux: deployOnLinux
    appServiceName: AppServiceName
    appServiceName2: AppServiceCertMasterName
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

module DeploymentSCEPmanConfig 'nestedtemplates/appConfig-scepman.bicep' = {
  name: 'DeploymentSCEPmanConfig'
  params: {
    StorageAccountTableUrl: SCEPmanStorageAccount.outputs.storageAccountTableUrl
    appServiceName: AppServiceName
    deployOnLinux: deployOnLinux
    scepManBaseURL: SCEPmanAppServices.outputs.scepmanURL
    keyVaultURL: SCEPmanVault.outputs.keyVaultURL
    caKeyType: caKeyType
    logAnalyticsWorkspaceId: AzureMonitor.outputs.workspaceId
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    OrgName: OrgName
    WebsiteArtifactsUri: ArtifactsLocationSCEPman
    license: license
    enableHealthCheck: enableHealthCheck
    updateChannel: updateChannel
  }
}

module DeploymentCertMasterConfig 'nestedtemplates/appConfig-certmaster.bicep' = {
  name: 'DeploymentCertMasterConfig'
  params: {
    appServiceName: AppServiceCertMasterName
    deployOnLinux: deployOnLinux
    scepmanUrl: SCEPmanAppServices.outputs.scepmanURL
    StorageAccountTableUrl: SCEPmanStorageAccount.outputs.storageAccountTableUrl
    logAnalyticsWorkspaceId: AzureMonitor.outputs.workspaceId
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    WebsiteArtifactsUri: ArtifactsLocationCertMaster
    enableHealthCheck: enableHealthCheck
    updateChannel: updateChannel
  }
}

module SCEPmanStorageAccount 'nestedtemplates/stgAccount.bicep' = {
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
