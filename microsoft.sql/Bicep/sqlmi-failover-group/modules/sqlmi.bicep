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

@description('Enter managed instance region. If you leave this field blank resource group location would be used.')
param location string = resourceGroup().location

@description('Enter secondary region. This will be used for the mandatory route to the secondary storage account.')
param secondaryStorageRegion string

@description('Enter virtual network name')
param virtualNetworkName string

@description('Enter virtual network address prefix.')
param addressPrefix string

@description('Enter subnet name.')
param subnetName string

@description('Enter subnet address prefix.')
param subnetPrefix string

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

param primaryManagedInstanceId string

var routeTableName = 'rt-${managedInstanceName}'
var networkSecurityGroupName = 'nsg-${managedInstanceName}'
var subnetPrefixString = replace(replace(subnetPrefix, '/', '-'), '.', '-')

resource routeTable 'Microsoft.Network/routeTables@2023-05-01' = {
  name: routeTableName
  location: location
  properties: {
    disableBgpRoutePropagation: false
  }
}

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: networkSecurityGroupName
  location: location
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
          destinationAddressPrefix: 'Storage.${location}'
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
          destinationAddressPrefix: 'Storage.${secondaryStorageRegion}'
          access: 'Allow'
          priority: 105
          direction: 'Outbound'
        }
      }
      {
        name: 'allow_tds_inbound'
        properties: {
          description: 'Allow TDS inbound traffic'
          priority: 1000
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '1433'
        }
      }
      {
        name: 'allow_redirect_inbound'
        properties: {
          description: 'Allow TDS redirect inbound traffic'
          priority: 1100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '11000-11999'
        }
      }
      {
        name: 'allow_geodr_inbound'
        properties: {
          description: 'Allow GeoDR inbound traffic'
          priority: 1200
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '5022'
        }
      }
      {
        name: 'deny_all_inbound'
        properties: {
          description: 'Deny all other inbound traffic'
          priority: 4096
          protocol: '*'
          access: 'Deny'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
      {
        name: 'allow_redirect_outbound'
        properties: {
          description: 'Allow redirect outbound traffic'
          priority: 1100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '11000-11999'
        }
      }
      {
        name: 'allow_geodr_outbound'
        properties: {
          description: 'Allow GeoDR outbound traffic'
          priority: 1200
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '5022'
        }
      }
      {
        name: 'deny_all_outbound'
        properties: {
          description: 'Deny all other outbound traffic'
          priority: 4096
          protocol: '*'
          access: 'Deny'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: virtualNetworkName
  location: location
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

resource managedInstance 'Microsoft.Sql/managedInstances@2023-02-01-preview' = {
  name: managedInstanceName
  location: location
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
    dnsZonePartner: primaryManagedInstanceId
  }
  dependsOn: [
    virtualNetwork
  ]
}

output managedInstanceId string = managedInstance.id
