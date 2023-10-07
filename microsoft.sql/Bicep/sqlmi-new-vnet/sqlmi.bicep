metadata name = 'Microsoft Azure SQL Managed Instance'
metadata description = 'Creates Azure SQL Managed Instance'
metadata owner = 'luis-aranda'

@description('Enter managed instance name.')
param managedInstanceName string

@description('Enter user name.')
param administratorLogin string

@description('Enter password.')
@secure()
param administratorLoginPassword string

@description('Enter primary region. This will be used for the mandatory route to the primary storage account and SQL MI location.If you leave this field blank resource group location would be used.')
param primaryRegion string = resourceGroup().location

@description('Enter secondary region. This will be used for the mandatory route to the secondary storage account.')
param secondaryRegion string

@description('Enter virtual network name. If you leave this field blank name will be created by the template.')
param virtualNetworkName string = 'SQLMI-VNET'

@description('Enter virtual network address prefix.')
param addressPrefix string = '10.0.0.0/16'

@description('Enter subnet name.')
param subnetName string = 'ManagedInstance'

@description('Enter subnet address prefix.')
param subnetPrefix string = '10.0.0.0/24'

@description('Enter sku name.')
@allowed([
  'GP_Gen5'
  'BC_Gen5'
])
param skuName string = 'GP_Gen5'

@description('Enter number of vCores.')
@allowed([
  4
  8
  16
  24
  32
  40
  64
  80
])
param vCores int = 4

@description('Enter storage size.')
@minValue(32)
@maxValue(8192)
param storageSizeInGB int = 32

@description('Enter license type.')
@allowed([
  'BasePrice'
  'LicenseIncluded'
])
param licenseType string = 'LicenseIncluded'

param allow_linkedserver bool = false

@description('Controls if public endpoint (port 3342) will be enabled')
param enable_public_endpoint bool = false

var networkSecurityGroupName = 'SQLMI-${managedInstanceName}-NSG'
var routeTableName = 'SQLMI-${managedInstanceName}-Route-Table'
var subnetPrefixString = replace(replace(subnetPrefix, '/', '-'), '.', '-')

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2020-06-01' = {
  name: networkSecurityGroupName
  location: primaryRegion
  properties: {
    securityRules: [
      {
        name: 'Microsoft.Sql-managedInstances_UseOnly_mi-healthprobe-in-${subnetPrefixString}-v11'
        properties: {
          description: 'Allow Azure Load Balancer inbound traffic'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: subnetPrefix
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'Microsoft.Sql-managedInstances_UseOnly_mi-internal-in-${subnetPrefixString}-v11'
        properties: {
          description: 'Allow MI internal inbound traffic'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: subnetPrefix
          destinationAddressPrefix: subnetPrefix
          access: 'Allow'
          priority: 101
          direction: 'Inbound'
        }
      }
      {
        name: 'Microsoft.Sql-managedInstances_UseOnly_mi-aad-out-${subnetPrefixString}-v11'
        properties: {
          description: 'Allow communication with Azure Active Directory over https'
          protocol: 'TCP'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: subnetPrefix
          destinationAddressPrefix: 'AzureActiveDirectory'
          access: 'Allow'
          priority: 101
          direction: 'Outbound'
        }
      }
      {
        name: 'Microsoft.Sql-managedInstances_UseOnly_mi-onedsc-out-${subnetPrefixString}-v11'
        properties: {
          description: 'Allow communication with the One DS Collector over https'
          protocol: 'TCP'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: subnetPrefix
          destinationAddressPrefix: 'OneDsCollector'
          access: 'Allow'
          priority: 102
          direction: 'Outbound'
        }
      }
      {
        name: 'Microsoft.Sql-managedInstances_UseOnly_mi-internal-out-${subnetPrefixString}-v11'
        properties: {
          description: 'Allow MI internal outbound traffic'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: subnetPrefix
          destinationAddressPrefix: subnetPrefix
          access: 'Allow'
          priority: 103
          direction: 'Outbound'
        }
      }
      {
        name: 'Microsoft.Sql-managedInstances_UseOnly_mi-strg-p-out-${subnetPrefixString}-v11'
        properties: {
          description: 'Allow outbound communication with storage primary over HTTPS'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: subnetPrefix
          destinationAddressPrefix: 'Storage.${primaryRegion}'
          access: 'Allow'
          priority: 104
          direction: 'Outbound'
        }
      }
      {
        name: 'Microsoft.Sql-managedInstances_UseOnly_mi-strg-s-out-${subnetPrefixString}-v11'
        properties: {
          description: 'Allow outbound communication with storage secondary over HTTPS'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: subnetPrefix
          destinationAddressPrefix: 'Storage.${secondaryRegion}'
          access: 'Allow'
          priority: 105
          direction: 'Outbound'
        }
      }
      {
        name: 'allow_redirect_inbound'
        properties: {
          description: 'Allow inbound redirect traffic to Managed Instance inside the virtual network'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '11000-11999'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1100
          direction: 'Inbound'
        }
      }
    ]
  }
}

resource nsg_public_endpoint 'Microsoft.Network/networkSecurityGroups/securityRules@2019-11-01' = if (enable_public_endpoint) {
  name: 'public_endpoint_inbound'
  parent: networkSecurityGroup
  properties: {
    description: 'Allow inbound traffic to Managed Instance through public endpoint'
    protocol: 'Tcp'
    sourcePortRange: '*'
    destinationPortRange: '3342'
    sourceAddressPrefix: '*'
    destinationAddressPrefix: '*'
    access: 'Allow'
    priority: 1200
    direction: 'Inbound'
  }

}

resource nsgrule_ls 'Microsoft.Network/networkSecurityGroups/securityRules@2019-11-01' = if (allow_linkedserver) {
  name: 'allow_linkedserver_outbound'
  parent: networkSecurityGroup
  properties: {
    description: 'Allows connecting to port 1433 for linked server from SQL MI'
    protocol: '*'
    sourcePortRange: '*'
    destinationPortRange: '1433'
    sourceAddressPrefix: '*'
    destinationAddressPrefix: 'VirtualNetwork'
    access: 'Allow'
    priority: 1301
    direction: 'Inbound'
  }
}

resource nsgrule_ls_redirect 'Microsoft.Network/networkSecurityGroups/securityRules@2019-11-01' = if (allow_linkedserver) {
  name: 'allow_redirect_outbound'
  parent: networkSecurityGroup
  properties: {
    description: 'Allows connecting to port range 11000-11999 for linked server from SQL MI'
    protocol: '*'
    sourcePortRange: '*'
    destinationPortRange: '11000-11999'
    sourceAddressPrefix: '*'
    destinationAddressPrefix: 'VirtualNetwork'
    access: 'Allow'
    priority: 1302
    direction: 'Inbound'
  }
}

resource routeTable 'Microsoft.Network/routeTables@2020-06-01' = {
  name: routeTableName
  location: primaryRegion
  properties: {
    disableBgpRoutePropagation: false
    routes: [
      {
        id: 'Microsoft.Sql-managedInstances_UseOnly_mi-AzureActiveDirectory'
        name: 'Microsoft.Sql-managedInstances_UseOnly_mi-AzureActiveDirectory'
        properties: {
          addressPrefix: 'AzureActiveDirectory'
          nextHopType: 'Internet'
        }
      }
      {
        id: 'Microsoft.Sql-managedInstances_UseOnly_mi-OneDsCollector'
        name: 'Microsoft.Sql-managedInstances_UseOnly_mi-OneDsCollector'
        properties: {
          addressPrefix: 'OneDsCollector'
          nextHopType: 'Internet'
        }
      }
      {
        id: 'Microsoft.Sql-managedInstances_UseOnly_mi-Storage.primaryRegion'
        name: 'Microsoft.Sql-managedInstances_UseOnly_mi-Storage.${primaryRegion}'
        properties: {
          addressPrefix: 'Storage.${primaryRegion}'
          nextHopType: 'Internet'
        }
      }
      {
        id: 'Microsoft.Sql-managedInstances_UseOnly_mi-Storage.secondaryRegion'
        name: 'Microsoft.Sql-managedInstances_UseOnly_mi-Storage.${secondaryRegion}'
        properties: {
          addressPrefix: 'Storage.${secondaryRegion}'
          nextHopType: 'Internet'
        }
      }
      {
        id: 'Microsoft.Sql-managedInstances_UseOnly_subnet-to-vnetlocal'
        name: 'Microsoft.Sql-managedInstances_UseOnly_subnet-${subnetPrefixString}-to-vnetlocal'
        properties: {
          addressPrefix: subnetPrefix
          nextHopType: 'VnetLocal'
        }
      }
    ]
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2020-06-01' = {
  name: virtualNetworkName
  location: primaryRegion
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: subnetPrefix
          routeTable: {
            id: routeTable.id
          }
          networkSecurityGroup: {
            id: networkSecurityGroup.id
          }
          delegations: [
            {
              name: 'managedInstanceDelegation'
              properties: {
                serviceName: 'Microsoft.Sql/managedInstances'
              }
            }
          ]
        }
      }
    ]
  }
}

resource managedInstance 'Microsoft.Sql/managedInstances@2020-02-02-preview' = {
  name: managedInstanceName
  location: primaryRegion
  sku: {
    name: skuName
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
    subnetId: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, subnetName)
    storageSizeInGB: storageSizeInGB
    vCores: vCores
    licenseType: licenseType
    publicDataEndpointEnabled: enable_public_endpoint
  }
  dependsOn: [
    virtualNetwork
  ]
}
