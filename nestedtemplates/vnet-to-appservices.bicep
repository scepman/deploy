@description('Name of the VNET')
param virtualNetworkName string

@description('Name of App Service')
param appServiceName string

@description('Region in which to create the vnet connection.')
param location string

resource appService 'Microsoft.Web/sites@2024-11-01' = {
  name: appServiceName
  location: location
  properties: {
    virtualNetworkSubnetId: resourceId(
      'Microsoft.Network/virtualNetworks/subnets',
      virtualNetworkName,
      'snet-scepman-appservices'
    )
  }
}
