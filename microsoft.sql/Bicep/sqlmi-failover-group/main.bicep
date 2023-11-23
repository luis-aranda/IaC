metadata name = 'Microsoft Azure SQL Managed Instance Failover Group'
metadata description = 'Creates Azure SQL Managed Instance Failover Group'
metadata owner = 'luis-aranda'

@description('Define a name prefix for the resources.')
param namePrefix string = 'fog'

@description('Enter primary managed instance location.')
@allowed([
  'BrazilSouth'
  'BrazilSoutheast'
  'CentralUS'
  'EastUS'
  'EastUS2'
  'NorthCentralUS'
  'SouthCentralUS'
  'WestCentralUS'
  'WestUS'
  'WestUS2'
  'WestUS3'
  'UKSouth'
])
param primaryManagedInstanceLocation string

@description('Enter the primary storage location for the primary managed instance')
param primaryManagedInstanceSecondaryStorageLocation string

@description('Enter virtual network address prefix.')
param primaryVirtualNetworkAddressPrefix string

@description('Enter subnet address prefix.')
param primarySubnetPrefix string

@description('Enter secondary managed instance location.')
@allowed([
  'BrazilSouth'
  'BrazilSoutheast'
  'CentralUS'
  'EastUS'
  'EastUS2'
  'NorthCentralUS'
  'SouthCentralUS'
  'WestCentralUS'
  'WestUS'
  'WestUS2'
  'WestUS3'
  'UKSouth'
])
param secondaryManagedInstanceLocation string

@description('Enter the secondary storage location for the secondary managed instance')
param secondaryManagedInstanceSecondaryStorageLocation string


@description('Enter virtual network address prefix.')
param secondaryVirtualNetworkAddressPrefix string

@description('Enter subnet address prefix.')
param secondarySubnetPrefix string

@description('Enter user name.')
param administratorLogin string

@description('Enter password.')
@secure()
param administratorLoginPassword string

@description('Enter the storage size in GB.')
param storageSizeinGB int = 32

@description('Enter the number of vCores.')
param vCores int = 4

@description('Enter sku name.')
@allowed([
  'GP_Gen5'
  'BC_Gen5'
])
param skuName string = 'GP_Gen5'

var location_short_name = {
  BrazilSouth: 'bs2'
  BrazilSoutheast: 'bs'
  CentralUS: 'cu'
  EastUS: 'eu'
  EastUS2: 'eu2'
  NorthCentralUS: 'ncu'
  SouthCentralUS: 'scu'
  WestCentralUS: 'wcu'
  WestUS: 'wu'
  WestUS2: 'wu2'
  WestUS3: 'wu3'
  UKSouth: 'us'
}

var primaryVirtualNetworkName = 'vnet-${namePrefix}-${location_short_name[primaryManagedInstanceLocation]}'
var secondaryVirtualNetworkName = 'vnet-${namePrefix}-${location_short_name[secondaryManagedInstanceLocation]}'

module primaryManagedInstance 'modules/sqlmi.bicep' = {
  name: 'Primary-SQLMI-Deployment'
  params: {
    managedInstanceName: 'sqlmi-${namePrefix}-${location_short_name[primaryManagedInstanceLocation]}'
    location: primaryManagedInstanceLocation
    secondaryStorageRegion: primaryManagedInstanceSecondaryStorageLocation
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
    virtualNetworkName: primaryVirtualNetworkName
    addressPrefix: primaryVirtualNetworkAddressPrefix
    subnetName: 'snet-${namePrefix}-${location_short_name[primaryManagedInstanceLocation]}'
    subnetPrefix: primarySubnetPrefix
    storageSizeInGB: storageSizeinGB
    vCores: vCores
    skuName: skuName
    primaryManagedInstanceId: ''
  }
}

module secondaryManagedInstance 'modules/sqlmi.bicep' = {
  name: 'Secondary-SQLMI-Deployment'
  params: {
    managedInstanceName: 'sqlmi-${namePrefix}-${location_short_name[secondaryManagedInstanceLocation]}'
    location: secondaryManagedInstanceLocation
    secondaryStorageRegion: secondaryManagedInstanceSecondaryStorageLocation
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
    virtualNetworkName: secondaryVirtualNetworkName
    addressPrefix: secondaryVirtualNetworkAddressPrefix
    subnetName: 'snet-${namePrefix}-${location_short_name[secondaryManagedInstanceLocation]}'
    subnetPrefix: secondarySubnetPrefix
    storageSizeInGB: storageSizeinGB
    vCores: vCores
    skuName: skuName
    primaryManagedInstanceId: primaryManagedInstance.outputs.managedInstanceId
  }
}

resource primaryVirtualNetwork 'Microsoft.Network/virtualNetworks@2023-05-01' existing = {
  name: primaryVirtualNetworkName
}

resource secondaryVirtualNetwork 'Microsoft.Network/virtualNetworks@2023-05-01' existing = {
  name: secondaryVirtualNetworkName
}

resource virtualNetworkPeeringPrimaryToSecondary 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-05-01' = {
  name: '${primaryVirtualNetworkName}-To-${secondaryVirtualNetworkName}'
  parent: primaryVirtualNetwork
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: secondaryVirtualNetwork.id
    }
  }
}

resource virtualNetworkPeeringSecondaryToPrimary 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-05-01' = {
  name: '${secondaryVirtualNetworkName}-To-${primaryVirtualNetworkName}'
  parent: secondaryVirtualNetwork
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: primaryVirtualNetwork.id
    }
  }
  dependsOn: [
    primaryManagedInstance
    secondaryManagedInstance
  ]
}
