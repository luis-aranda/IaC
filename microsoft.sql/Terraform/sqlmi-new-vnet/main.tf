#############################################################################
# TERRAFORM CONFIG
#############################################################################

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 2.97.0"
    }
  }
  backend "azurerm" {
    resource_group_name  = "rg-hub-scus"
    storage_account_name = "lacsa"
    container_name       = "terraform-state"
    key                  = "managedinstance.tfstate"
  }
}

##################################################################################
# PROVIDERS
##################################################################################

provider "azurerm" {
  features {}
}

#############################################################################
# VARIABLES
#############################################################################

variable "location" {
  type    = string
  default = "East US"
  validation {
    condition = contains([
    "Brazil South", "Brazil Southeast", "Central US", "East US", "East US 2", "North Central US", "South Central US", "West Central US", "West US", "West US 2", "West US 3"], var.location)
    error_message = "Argument 'location' must be one of 'Brazil South', 'Brazil Southeast', 'Central US', 'East US', 'East US 2', 'North Central US', 'South Central US', 'West Central US', 'West US', 'West US 2', 'West US 3'."
  }
}

variable "naming_prefix" {
  type    = string
  default = "it-tf"
}

variable "vnet_cidr_range" {
  type    = string
  default = "10.0.0.0/16"
}

variable "subnet_prefix" {
  type    = list(string)
  default = ["10.0.0.0/24"]
}

variable "sku_name" {
  type    = string
  default = "GP_Gen5"
  validation {
    condition     = contains(["GP_Gen5", "BC_Gen5"], var.sku_name)
    error_message = "Argument 'sku_name' must be one of 'GP_Gen5' or 'BC_Gen5'."
  }
}

variable "vCores" {
  type    = number
  default = 4
  validation {
    condition     = contains([4, 8, 16, 24, 32, 40, 64, 80], var.vCores)
    error_message = "Argument 'vCores' must be one of 4, 8, 16, 24, 32, 40, 64 or 80."
  }
}

variable "storage_size_in_gb" {
  type    = number
  default = 32
  validation {
    condition     = var.storage_size_in_gb > 31 && var.storage_size_in_gb < 8193
    error_message = "Argument 'storage_size_in_gb' must be greater than 32 and less than 8192."
  }
}

variable "license_type" {
  type    = string
  default = "LicenseIncluded"
  validation {
    condition     = contains(["BasePrice", "LicenseIncluded"], var.license_type)
    error_message = "Argument 'license_type' must be one of 'BasePrice','LicenseIncluded'."
  }
}

variable "proxy_override" {
  type    = string
  default = "Proxy"
  validation {
    condition     = contains(["Default", "Proxy", "Redirect"], var.proxy_override)
    error_message = "Argument 'proxy_override' must be one of 'Default', 'Proxy', 'Redirect'."
  }
}

variable "location_short_name" {
  type = map(string)
  default = {
    "Brazil South"     = "bs2",
    "Brazil Southeast" = "bs",
    "Central US"       = "cu",
    "East US"          = "eu",
    "East US 2"        = "eu2",
    "North Central US" = "ncu",
    "South Central US" = "scu",
    "West Central US"  = "wcu",
    "West US"          = "wu",
    "West US 2"        = "wu2",
    "West US 3"        = "wu3"
  }
}

variable "enable_public_endpoint" {
  type    = bool
  default = false
}

variable "kv_rg_name" {
  type        = string
  description = "Resource group name of the Key Vault that has the SQL Admin credentials"
}

variable "kv_name" {
  type        = string
  description = "Name of the Key Vault that has the SQL Admin credentials"
}

locals {
  suffix = "${var.naming_prefix}-${terraform.workspace}-${var.location_short_name[var.location]}"
}

##################################################################################
# RESOURCES
##################################################################################

resource "azurerm_resource_group" "rg" {
  name     = "rg-${local.suffix}"
  location = var.location
  tags = {
    environment = terraform.workspace
  }
}

resource "azurerm_network_security_group" "nsg" {
  name                = "nsg-${local.suffix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_network_security_rule" "allow_management_inbound" {
  name                        = "allow_management_inbound"
  priority                    = 106
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = ["9000", "9003", "1438", "1440", "1452"]
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.nsg.name
}

resource "azurerm_network_security_rule" "allow_misubnet_inbound" {
  name                        = "allow_misubnet_inbound"
  priority                    = 200
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "10.0.0.0/24"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.nsg.name
}

resource "azurerm_network_security_rule" "allow_health_probe_inbound" {
  name                        = "allow_health_probe_inbound"
  priority                    = 300
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "AzureLoadBalancer"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.nsg.name
}

resource "azurerm_network_security_rule" "allow_tds_inbound" {
  name                        = "allow_tds_inbound"
  priority                    = 1000
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "1433"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.nsg.name
}

resource "azurerm_network_security_rule" "public_endpoint_inbound" {
  count                       = var.enable_public_endpoint == false ? 0 : 1
  name                        = "public_endpoint_inbound"
  priority                    = 1100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "3342"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.nsg.name
}

resource "azurerm_network_security_rule" "deny_all_inbound" {
  name                        = "deny_all_inbound"
  priority                    = 4096
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.nsg.name
}

resource "azurerm_network_security_rule" "allow_management_outbound" {
  name                        = "allow_management_outbound"
  priority                    = 102
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = ["80", "443", "12000"]
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.nsg.name
}

resource "azurerm_network_security_rule" "allow_misubnet_outbound" {
  name                        = "allow_misubnet_outbound"
  priority                    = 200
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "10.0.0.0/24"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.nsg.name
}

resource "azurerm_network_security_rule" "deny_all_outbound" {
  name                        = "deny_all_outbound"
  priority                    = 4096
  direction                   = "Outbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.nsg.name
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${local.suffix}"
  address_space       = [var.vnet_cidr_range]
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "subnet-mi"
  address_prefixes     = var.subnet_prefix
  virtual_network_name = azurerm_virtual_network.vnet.name
  resource_group_name  = azurerm_resource_group.rg.name

  delegation {
    name = "managedinstancedelegation"

    service_delegation {
      name    = "Microsoft.Sql/managedInstances"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action", "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action", "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action"]
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_route_table" "rt" {
  name                          = "rt-${local.suffix}"
  location                      = var.location
  resource_group_name           = azurerm_resource_group.rg.name
  disable_bgp_route_propagation = false
  depends_on = [
    azurerm_subnet.subnet,
  ]
}

resource "azurerm_subnet_route_table_association" "subnet_rt_association" {
  subnet_id      = azurerm_subnet.subnet.id
  route_table_id = azurerm_route_table.rt.id
}

data "azurerm_key_vault" "kv" {
  name                = var.kv_name
  resource_group_name = var.kv_rg_name
}

data "azurerm_key_vault_secret" "administrator_login" {
  name         = "managedSqlUsernameKey"
  key_vault_id = data.azurerm_key_vault.kv.id
}

data "azurerm_key_vault_secret" "administrator_login_password" {
  name         = "managedSqlPasswordKey"
  key_vault_id = data.azurerm_key_vault.kv.id
}

resource "azurerm_sql_managed_instance" "sqlmi" {
  name                         = "sqlmi-${local.suffix}"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = var.location
  administrator_login          = data.azurerm_key_vault_secret.administrator_login.value
  administrator_login_password = data.azurerm_key_vault_secret.administrator_login_password.value
  license_type                 = var.license_type
  subnet_id                    = azurerm_subnet.subnet.id
  sku_name                     = var.sku_name
  vcores                       = var.vCores
  storage_size_in_gb           = var.storage_size_in_gb
  public_data_endpoint_enabled = var.enable_public_endpoint
  proxy_override               = var.proxy_override

  depends_on = [
    azurerm_subnet_network_security_group_association.subnet_nsg_association,
    azurerm_subnet_route_table_association.subnet_rt_association
  ]
}

#############################################################################
# LOCAL FILE
#############################################################################




##################################################################################
# OUTPUT
##################################################################################

output "resource-group-name" {
  value = azurerm_resource_group.rg.name
}

output "sqlmi-name" {
  value = azurerm_sql_managed_instance.sqlmi.name
}
