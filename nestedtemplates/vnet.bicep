@description('Specifies the name of the Virtual Network.')
param virtualNetworkName string

@description('The Azure Region where the Virtual Network will be created.')
param location string

@description('Tags to be assigned to the created resources.')
param resourceTags object

@description('Name of the Network Security Group applied to the subnets.')
param networkSecurityGroupName string = 'nsg-${virtualNetworkName}'

@description('List of address prefixes for the Virtual Network.')
param virtualNetworkAddressPrefixes array = [
  '10.142.0.0/16'
]

@description('Subnet prefix for the default subnet')
param subnetIpPrefixDefault string ='10.142.0.0/24'

@description('Subnet prefix for the subnet that will host the App Services')
param subnetIpPrefixScepman string = '10.142.1.0/24'

resource subnetNsg 'Microsoft.Network/networkSecurityGroups@2025-05-01' = {
  name: networkSecurityGroupName
  location: location
  tags: resourceTags
  properties: {}
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2025-05-01' = {
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
        properties: {
          addressPrefix: subnetIpPrefixDefault
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          defaultOutboundAccess: false
          networkSecurityGroup: {
            id: subnetNsg.id
          }
        }
      }
      {
        name: 'snet-scepman-appservices'
        properties: {
          addressPrefix: subnetIpPrefixScepman
          delegations: [
            {
              name: 'delegation'
              properties: {
                serviceName: 'Microsoft.Web/serverfarms'
              }
            }
          ]
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          defaultOutboundAccess: false
          networkSecurityGroup: {
            id: subnetNsg.id
          }
        }
      }
    ]
    enableDdosProtection: false
  }
}
