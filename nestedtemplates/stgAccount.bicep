@description('Name of the storage account')
param StorageAccountName string

@description('Location where the resources will be deployed')
param location string

@description('Tags to be assigned to the created resources')
param resourceTags object

@description('IDs of Principals that shall receive table contributor rights on the storage account')
param tableContributorPrincipals array

@description('Name of the Virtual Network to associate with the table service of the storage account.')
param virtualNetworkName string

@description('Name of the private endpoint to be created for the table service of the storage account. Pass \'None\' if you don\'t want to create a private endpoint.')
param privateEndpointName string

// The A record is only created if you use a magic name
// See: https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns#storage
var privateDnsZoneName = 'privatelink.table.${environment().suffixes.storage}'

// Regions where GZRS (Geo-Zone Redundant Storage) is supported
// These regions have BOTH Availability Zones AND a Paired Region
// Based on: https://learn.microsoft.com/en-us/azure/reliability/regions-list
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
  'japanwest'
  'koreacentral'
  'northeurope'
  'norwayeast'
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
  'usgovvirginia' // Has Availability Zones according to https://cloudsteak.com/azure-us-gov-virginia-availability-zones-now-generally-available/
                  // Is paired according to https://learn.microsoft.com/en-us/azure/azure-government/documentation-government-welcome#region-pairing
                  // Name is based on the pattern observed in US Gov regions and specified here (unofficial source): https://www.azurespeed.com/Information/AzureUSGovernmentRegions
  'chinanorth3'   // Has both Availability Zones and a paired region according to https://learn.microsoft.com/en-us/azure/china/overview-regions
]

// Regions where ZRS (Zone Redundant Storage) is supported
// These regions have Availability Zone support
// Based on: https://learn.microsoft.com/en-us/azure/reliability/regions-list
var zrsRegions = [
  'australiaeast'
  'austriaeast'
  'belgiumcentral'
  'brazilsouth'
  'canadacentral'
  'centralindia'
  'centralus'
  'chilecentral'
  'eastasia'
  'eastus'
  'eastus2'
  'francecentral'
  'germanywestcentral'
  'indonesiacentral'
  'israelcentral'
  'italynorth'
  'japaneast'
  'japanwest'
  'koreacentral'
  'malaysiawest'
  'mexicocentral'
  'newzealandnorth'
  'northeurope'
  'norwayeast'
  'polandcentral'
  'qatarcentral'
  'southafricanorth'
  'southcentralus'
  'southeastasia'
  'spaincentral'
  'swedencentral'
  'switzerlandnorth'
  'uaenorth'
  'uksouth'
  'westeurope'
  'westus2'
  'westus3'
  'usgovvirginia' // Has Availability Zones according to https://cloudsteak.com/azure-us-gov-virginia-availability-zones-now-generally-available/
                  // Name is based on the pattern observed in US Gov regions and specified here (unofficial source): https://www.azurespeed.com/Information/AzureUSGovernmentRegions
  'chinanorth3'   // Has Availability Zones according to https://learn.microsoft.com/en-us/azure/china/overview-regions
]

// Regions with geo-redundant support (have a Paired Region)
// These regions support GRS (Geo-Redundant Storage)
// Based on: https://learn.microsoft.com/en-us/azure/reliability/regions-list
var geoRedundantRegions = [
  'australiacentral'
  'australiacentral2'
  'australiaeast'
  'australiasoutheast'
  'brazilsouth'
  'brazilsoutheast'
  'canadacentral'
  'canadaeast'
  'centralindia'
  'centralus'
  'eastasia'
  'eastus'
  'eastus2'
  'francecentral'
  'francesouth'
  'germanynorth'
  'germanywestcentral'
  'japaneast'
  'japanwest'
  'koreacentral'
  'koreasouth'
  'northcentralus'
  'northeurope'
  'norwayeast'
  'norwaywest'
  'southafricanorth'
  'southafricawest'
  'southcentralus'
  'southindia'
  'southeastasia'
  'swedencentral'
  'switzerlandnorth'
  'switzerlandwest'
  'uaecentral'
  'uaenorth'
  'uksouth'
  'ukwest'
  'westcentralus'
  'westeurope'
  'westindia'
  'westus'
  'westus2'
  'westus3'
                // US Gov names are based on the pattern observed in US Gov regions and specified here (unofficial source): https://www.azurespeed.com/Information/AzureUSGovernmentRegions
  'usgovvirginia' // Is paired according to https://learn.microsoft.com/en-us/azure/azure-government/documentation-government-welcome#region-pairing
  'usgovarizona'
  'usgovtexas'  // I read https://learn.microsoft.com/en-us/azure/azure-government/documentation-government-welcome#region-pairing such that Texas is paired with both other gov regions, but check this: maybe it is actually unpaired or paired with itself?

  'usdodcentral' // supposedly paired with usdodeast, but the official source doesn't say it: https://learn.microsoft.com/en-us/azure/azure-government/documentation-government-overview-dod
  'usdodeast'    // supposedly paired with usdodcentral

              // Azure in China names are pattern-based, not tested
              // Here's the list that says whether they are paired: https://learn.microsoft.com/en-us/azure/china/overview-regions
  'chinaeast'
  'chinaeast2'
  'chinaeast3'
  'chinanorth'
  'chinanorth2'
  'chinanorth3'
]

// Determine the appropriate storage account SKU based on region support
// Priority: GZRS (AZ + Paired) > GRS (Paired) > ZRS (AZ) > LRS (Default)
// This ensures the best available redundancy option for each region while maintaining deployment reliability
var storageAccountSku = contains(gzrsRegions, location) ? 'Standard_GZRS' : (contains(geoRedundantRegions, location) ? 'Standard_GRS' : (contains(zrsRegions, location) ? 'Standard_ZRS' : 'Standard_LRS'))

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
    publicNetworkAccess: ((privateEndpointName == 'None') ? 'Enabled' : 'Disabled')
    networkAcls: {
      bypass: 'None'
      defaultAction: ((privateEndpointName == 'None') ? 'Allow' : 'Deny')
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

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (privateEndpointName != 'None') {
  name: privateDnsZoneName
  location: 'Global'
  tags: resourceTags
  properties: {}
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = if (privateEndpointName != 'None') {
  name: privateEndpointName
  location: location
  tags: resourceTags
  properties: {
    subnet: {
      id: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, 'default')
    }
    privateLinkServiceConnections: [
      {
        name: 'tableStorageConnection'
        properties: {
          privateLinkServiceId: StorageAccount.id
          groupIds: [
            'table'
          ]
          privateLinkServiceConnectionState: {
            status: 'Approved'
            description: 'Private endpoint connection approved'
            actionsRequired: 'None'
          }
        }
      }
    ]
  }
}

resource privateEndpointName_default 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-06-01' = if (privateEndpointName != 'None') {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: privateDnsZoneName
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

resource privateDnsZoneName_StorageAccountName_link 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (privateEndpointName != 'None') {
  parent: privateDnsZone
  name: '${StorageAccountName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: resourceId('Microsoft.Network/virtualNetworks', virtualNetworkName)
    }
  }
}

output storageAccountTableUrl string = StorageAccount.properties.primaryEndpoints.table
