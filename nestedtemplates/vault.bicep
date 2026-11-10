@description('Specifies the name of the key vault.')
@minLength(3)
@maxLength(24)
param keyVaultName string

@description('Use an existing key vault with the given name in the target resource group instead of creating a new one. It must use the Azure RBAC permission model.')
param useExistingKeyVault bool = false

@description('ID of SCEPman app service principal, whom will be assigned permissions to the KV')
param permittedPrincipalId string

@description('Secrets to store in the key vault as name-value pairs. Secrets with empty values are skipped.')
@secure()
param secrets object = {}

@description('Region in which to create the key vault.')
param location string

@description('Tags to be assigned to the created resources')
param resourceTags object

@description('Name of the Virtual Network to associate with the key vault.')
param virtualNetworkName string

@description('Name of the private endpoint to be created for the key vault. Select \'None\' to not create a private endpoint.')
param privateEndpointName string

var rbac_roles = [
  '14b46e9e-c2b7-41b4-b07b-48a6ebf60603' // Key Vault Crypto Officer
  'a4417e6f-fecd-4de8-b567-7b0420556985' // Key Vault Certificates Officer
  '4633458b-17de-408a-b874-0445c86b69e6' // Key Vault Secrets User
]

resource newKeyVault 'Microsoft.KeyVault/vaults@2026-05-15' = if (!useExistingKeyVault) {
  name: keyVaultName
  location: location
  tags: resourceTags
  properties: {
    tenantId: subscription().tenantId
    enabledForDeployment: false
    enabledForTemplateDeployment: false
    enablePurgeProtection: true
    enableSoftDelete: true
    enabledForDiskEncryption: false
    enableRbacAuthorization: true
    sku: {
      name: 'premium'
      family: 'A'
    }
    publicNetworkAccess: ((privateEndpointName == 'None') ? 'Enabled' : 'Disabled')
    networkAcls: {
      bypass: 'None'
      defaultAction: ((privateEndpointName == 'None') ? 'Allow' : 'Deny')
    }
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2026-05-15' existing = {
  name: keyVaultName
}

resource roleAssignment_kv_rbac_roles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for item in rbac_roles: {
    scope: keyVault
    name: guid('roleAssignment-kv-${item}-${permittedPrincipalId}')
    properties: {
      roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', item)
      principalId: permittedPrincipalId
    }
    dependsOn: [
      newKeyVault
    ]
  }
]

resource keyVaultSecrets 'Microsoft.KeyVault/vaults/secrets@2026-05-15' = [
  for secret in filter(items(secrets), secret => !empty(secret.value)): {
    parent: keyVault
    name: secret.key
    properties: {
      value: secret.value
    }
    dependsOn: [
      newKeyVault
    ]
  }
]

resource privatelink_vaultcore_azure_net 'Microsoft.Network/privateDnsZones@2024-06-01' = if (privateEndpointName != 'None') {
  name: 'privatelink.vaultcore.azure.net' // The A record is only created if you use this magic name
                                          // See: https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns#security
                                          // It would be preferable to use the environment function (see https://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/template-functions-deployment#environment),
                                          // but presumably it doesn't yet work for this case: https://github.com/Azure/bicep/issues/9839
  location: 'Global'
  tags: resourceTags
  properties: {}
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2026-01-01' = if (privateEndpointName != 'None') {
  name: privateEndpointName
  location: location
  tags: resourceTags
  properties: {
    subnet: {
      id: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, 'default')
    }
    privateLinkServiceConnections: [
      {
        name: 'keyVault'
        properties: {
          privateLinkServiceId: newKeyVault.id
          groupIds: [
            'vault'
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

resource privateEndpointName_default 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2026-01-01' = if (privateEndpointName != 'None') {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink.vaultcore.azure.net'
        properties: {
          privateDnsZoneId: privatelink_vaultcore_azure_net.id
        }
      }
    ]
  }
}

resource privatelink_vaultcore_azure_net_keyVaultName_link 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = if (privateEndpointName != 'None') {
  parent: privatelink_vaultcore_azure_net
  name: '${keyVaultName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: resourceId('Microsoft.Network/virtualNetworks', virtualNetworkName)
    }
  }
}

output keyVaultURL string = useExistingKeyVault ? keyVault.properties.vaultUri : newKeyVault!.properties.vaultUri
