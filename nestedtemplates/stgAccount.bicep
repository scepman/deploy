@description('Name of the storage account')
param StorageAccountName string

@description('Location where the resources will be deployed')
param location string

@description('Tags to be assigned to the created resources')
param resourceTags object

@description('IDs of Principals that shall receive table contributor rights on the storage account')
param tableContributorPrincipals array

@description('Name of the Virtual Network to associate with the table service of the storage account. Pass \'None\' if you don\'t want to use a Virtual Network.')
param virtualNetworkName string

// Regions where GZRS (Geo-Zone Redundant Storage) is supported
// Based on: https://learn.microsoft.com/en-us/azure/storage/common/redundancy-regions-gzrs
var gzrsRegions = [
  'australiaeast'
  'brazilsouth'
  'canadacentral'
  'centralindia'
  'centralus'
  'eastasia'
  'eastus'
  'eastus2'
  'francecentral'
  'germanywestcentral'
  'japaneast'
  'koreacentral'
  'northeurope'
  'norwayeast'
  'qatarcentral'
  'southafricanorth'
  'southcentralus'
  'southeastasia'
  'swedencentral'
  'switzerlandnorth'
  'uaenorth'
  'uksouth'
  'westeurope'
  'westus2'
  'westus3'
]

// Regions where ZRS (Zone Redundant Storage) is supported as fallback
// Based on: https://learn.microsoft.com/en-us/azure/storage/common/redundancy-regions-zrs
var zrsRegions = [
  'australiaeast'
  'brazilsouth'
  'canadacentral'
  'centralindia'
  'centralus'
  'eastasia'
  'eastus'
  'eastus2'
  'francecentral'
  'germanywestcentral'
  'japaneast'
  'koreacentral'
  'northeurope'
  'norwayeast'
  'qatarcentral'
  'southafricanorth'
  'southcentralus'
  'southeastasia'
  'swedencentral'
  'switzerlandnorth'
  'uaenorth'
  'uksouth'
  'westeurope'
  'westus2'
  'westus3'
  // Additional regions that support ZRS but may not support GZRS
  'australiasoutheast'
  'canadaeast'
  'centraluseuap'
  'eastus2euap'
  'japanwest'
  'koreasouth'
  'northcentralus'
  'southindia'
  'ukwest'
  'westcentralus'
  'westus'
]

// Determine the appropriate storage account SKU based on region support
// Priority: GZRS > ZRS > LRS
// This ensures the best available redundancy option for each region while maintaining deployment reliability
var storageAccountSku = contains(gzrsRegions, location) ? 'Standard_GZRS' : (contains(zrsRegions, location) ? 'Standard_ZRS' : 'Standard_LRS')

resource StorageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: StorageAccountName
  location: location
  tags: resourceTags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowCrossTenantReplication: false
    allowSharedKeyAccess: false
    isHnsEnabled: false
    isNfsV3Enabled: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      bypass: 'None'
      defaultAction: ((virtualNetworkName == 'None') ? 'Allow' : 'Deny')
      virtualNetworkRules: [
        {
          id: resourceId(
            'Microsoft.Network/virtualNetworks/subnets',
            virtualNetworkName,
            'snet-scepman-appservices'
          )
          action: 'Allow'
        }
      ]
    }
  }
}

resource roleAssignment_sa_tableContributorPrincipals 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for item in tableContributorPrincipals: {
    scope: StorageAccount
    name: guid('roleAssignment-sa-${item}-tableContributor')
    properties: {
      roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3') //0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3 is Storage Table Data Contributor
      principalId: item
    }
  }
]

output storageAccountTableUrl string = StorageAccount.properties.primaryEndpoints.table
