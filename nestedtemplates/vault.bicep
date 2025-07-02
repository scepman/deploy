@description('Specifies the name of the key vault.')
@minLength(3)
@maxLength(24)
param keyVaultName string

@description('ID of SCEPman app service principal, whom will be assigned permissions to the KV')
param permittedPrincipalId string

@description('Region in which to create the key vault.')
param location string

@description('Tags to be assigned to the created resources')
param resourceTags object

@description('Name of the Virtual Network to associate with the key vault. Pass \'None\' if you don\'t want to use a Virtual Network.')
param virtualNetworkName string

var rbac_roles = [
  '14b46e9e-c2b7-41b4-b07b-48a6ebf60603' // Key Vault Crypto Officer
  'a4417e6f-fecd-4de8-b567-7b0420556985' // Key Vault Certificates Officer
  '4633458b-17de-408a-b874-0445c86b69e6' // Key Vault Secrets User
]

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
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
          ignoreMissingVnetServiceEndpoint: false
        }
      ]
    }
  }
}

resource roleAssignment_kv_rbac_roles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for item in rbac_roles: {
    scope: keyVault
    name: guid('roleAssignment-kv-${item}-${permittedPrincipalId}')
    properties: {
      roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', item)
      principalId: permittedPrincipalId
    }
  }
]

output keyVaultURL string = keyVault.properties.vaultUri
