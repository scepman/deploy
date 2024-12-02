@description('Specifies the name of the Virtual Network.')
param virtualNetworkName string

@description('The Azure Region where the Virtual Network will be created.')
param location string

@description('Tags to be assigned to the created resources.')
param resourceTags object

@description('List of address prefixes for the Virtual Network.')
param virtualNetworkAddressPrefixes array = [
  '10.142.0.0/16'
]

@description('Subnet prefix for the default subnet')
param subnetIpPrefixDefault string ='10.142.0.0/24'

@description('Subnet prefix for the subnet that will host the App Services')
param subnetIpPrefixScepman string = '10.142.1.0/24'

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-06-01' = {
  name: virtualNetworkName
  location: location
  tags: resourceTags
  properties: {
    addressSpace: {
      addressPrefixes: virtualNetworkAddressPrefixes
    }
    encryption: {
      enabled: false
      enforcement: 'AllowUnencrypted'
    }
    subnets: [
      {
        name: 'default'
        id: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, 'default')
        properties: {
          addressPrefix: subnetIpPrefixDefault
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          defaultOutboundAccess: true
        }
        type: 'Microsoft.Network/virtualNetworks/subnets'
      }
      {
        name: 'snet-scepman-appservices'
        id: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, 'snet-scepman-appservices')
        properties: {
          addressPrefix: subnetIpPrefixScepman
          delegations: [
            {
              name: 'delegation'
              id: resourceId(
                'Microsoft.Network/virtualNetworks/subnets/delegations',
                virtualNetworkName,
                'snet-scepman-appservices',
                'delegation'
              )
              properties: {
                serviceName: 'Microsoft.Web/serverfarms'
              }
              type: 'Microsoft.Network/virtualNetworks/subnets/delegations'
            }
          ]
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
        type: 'Microsoft.Network/virtualNetworks/subnets'
      }
    ]
    enableDdosProtection: false
  }
}
