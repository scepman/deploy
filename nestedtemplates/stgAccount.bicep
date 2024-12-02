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

resource StorageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: StorageAccountName
  location: location
  tags: resourceTags
  sku: {
    name: 'Standard_LRS'
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
      defaultAction: ((privateEndpointName == 'None') ? 'Allow' : 'Deny')
    }
  }
}

resource roleAssignment_sa_tableContributorPrincipals 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for item in tableContributorPrincipals: {
    scope: StorageAccount
    name: guid('roleAssignment-sa-${item}')
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
