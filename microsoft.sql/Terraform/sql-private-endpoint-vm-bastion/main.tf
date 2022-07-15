##################################################################################
# TERRAFORM CONFIG
##################################################################################

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
    key                  = "sqlprivateendpoint.tfstate"
  }
}

##################################################################################
# PROVIDERS
##################################################################################

provider "azurerm" {
  features {}
}

##################################################################################
# VARIABLES
##################################################################################

variable "location" {
  type    = string
  default = "East US"
  validation {
    condition = contains([
    "Brazil South", "Brazil Southeast", "Central US", "East US", "East US 2", "North Central US", "South Central US", "West Central US", "West US", "West US 2", "West US 3", "UK South"], var.location)
    error_message = "Argument 'location' must be one of 'Brazil South', 'Brazil Southeast', 'Central US', 'East US', 'East US 2', 'North Central US', 'South Central US', 'West Central US', 'West US', 'West US 2', 'West US 3'."
  }
}

variable "naming_prefix" {
  type    = string
  default = "it-tf"
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
    "West US 3"        = "wu3",
    "UK South"         = "us"
  }
}

variable "vnet_cidr_range" {
  type    = string
  default = "10.0.0.0/16"
}

variable "subnet_config" {
  type    = list(string)
  default = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
}

variable "rg_kv" {
  type    = string
  default = "rg-hub-scus"
}

variable "kv" {
  type    = string
  default = "lackv"
}

variable "vm_size" {
  type    = string
  default = "Standard_B1ms"
}

variable "vm_os_publisher" {
  type    = string
  default = "canonical"
}

variable "vm_os_offer" {
  type    = string
  default = "0001-com-ubuntu-server-focal"

}
variable "vm_os_sku" {
  type    = string
  default = "20_04-lts-gen2"
}

variable "ssh_key_path" {
  type    = string
  default = "C:\\Users\\luaranda\\.ssh\\terraform.pub"
}

variable "vm_os" {
  type    = string
  default = "Linux"
  validation {
    condition     = contains(["Linux", "Windows"], var.vm_os)
    error_message = "Argument 'vm_os' must be one of 'Linux', 'Windows'."
  }
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

module "vnet" {
  source              = "Azure/vnet/azurerm"
  vnet_name           = "vnet-${local.suffix}"
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = [var.vnet_cidr_range]
  subnet_prefixes     = var.subnet_config
  subnet_names        = ["AzureBastionSubnet", "snet-vm", "snet-sql"]

  tags = {
    environment = terraform.workspace
  }

  subnet_enforce_private_link_endpoint_network_policies = {
    "snet-sql" : true
  }

  nsg_ids = {
    AzureBastionSubnet = azurerm_network_security_group.nsg-bas.id
    snet-vm            = azurerm_network_security_group.nsg-vm.id
    snet-sql           = azurerm_network_security_group.nsg-sql.id
  }

  depends_on = [
    azurerm_resource_group.rg,
    azurerm_network_security_group.nsg-bas,
    azurerm_network_security_group.nsg-vm,
    azurerm_network_security_group.nsg-sql
  ]
}

data "template_file" "userdata" {
  template = file("userdata.yaml")
}

module "linuxservers" {
  count               = var.vm_os == "Linux" ? 1 : 0
  source              = "Azure/compute/azurerm"
  vm_hostname         = "vm-${local.suffix}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  vm_size             = var.vm_size
  vm_os_publisher     = var.vm_os_publisher
  vm_os_offer         = var.vm_os_offer
  vm_os_sku           = var.vm_os_sku
  nb_public_ip        = 0
  vnet_subnet_id      = data.azurerm_subnet.snet-vm.id
  ssh_key             = var.ssh_key_path
  custom_data         = data.template_file.userdata.rendered
  identity_type       = "SystemAssigned"

  tags = {
    environment = terraform.workspace
  }

  depends_on = [
    azurerm_resource_group.rg,
    azurerm_network_security_group.nsg-vm
  ]
}

resource "azurerm_network_security_group" "nsg-bas" {
  name                = "nsg-bas"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  security_rule {
    name                       = "AllowHttpsInbound"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowGatewayManagerInbound"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "433"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowAzureLoadBalancerInbound"
    priority                   = 140
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "433"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowBastionHostCommunication"
    priority                   = 150
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = [8080, 5701]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowSshRdpOutbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_ranges    = [22, 3389]
    source_address_prefix      = "*"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowAzureCloudOutbound"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "AzureCloud"
  }

  security_rule {
    name                       = "AllowBastionCommunication"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_ranges    = [8080, 5701]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowGetSessionInformation"
    priority                   = 130
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }
}

resource "azurerm_network_security_group" "nsg-vm" {
  name                = "nsg-vm"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  security_rule {
    name                       = "allow_ssh_inbound"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow_rdp_inbound"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "1433"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "nsg-sql" {
  name                = "nsg-sql"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  security_rule {
    name                       = "allow_tds_inbound"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "1433"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
}

resource "azurerm_public_ip" "pip-bastion" {
  name                = "pip-${local.suffix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

data "azurerm_virtual_network" "vnet" {
  resource_group_name = azurerm_resource_group.rg.name
  name                = "vnet-${local.suffix}"

  depends_on = [
    module.vnet
  ]
}

data "azurerm_subnet" "snet-bas" {
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = "vnet-${local.suffix}"
  name                 = "AzureBastionSubnet"

  depends_on = [
    module.vnet
  ]
}

data "azurerm_subnet" "snet-vm" {
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = "vnet-${local.suffix}"
  name                 = "snet-vm"

  depends_on = [
    module.vnet
  ]
}

data "azurerm_subnet" "snet-sql" {
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = "vnet-${local.suffix}"
  name                 = "snet-sql"

  depends_on = [
    module.vnet
  ]
}

resource "azurerm_bastion_host" "bastion" {
  name                = "bas-${local.suffix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                 = "configuration"
    subnet_id            = data.azurerm_subnet.snet-bas.id
    public_ip_address_id = azurerm_public_ip.pip-bastion.id
  }
}

data "azurerm_key_vault" "kv" {
  resource_group_name = var.rg_kv
  name                = var.kv
}

data "azurerm_key_vault_secret" "kv-administrator-login" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "managedSqlUsernameKey"
}

data "azurerm_key_vault_secret" "kv-administrator-password" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "managedSqlPasswordKey"
}

resource "azurerm_mssql_server" "sql" {
  resource_group_name           = azurerm_resource_group.rg.name
  location                      = azurerm_resource_group.rg.location
  version                       = "12.0"
  name                          = "sql-${local.suffix}"
  administrator_login           = data.azurerm_key_vault_secret.kv-administrator-login.value
  administrator_login_password  = data.azurerm_key_vault_secret.kv-administrator-password.value
  public_network_access_enabled = "false"

  tags = {
    environment = terraform.workspace
  }
}

resource "azurerm_mssql_database" "sqldb" {
  server_id   = azurerm_mssql_server.sql.id
  name        = "sqldb-${local.suffix}"
  sku_name    = "Basic"
  sample_name = "AdventureWorksLT"
}

resource "azurerm_private_endpoint" "sql-private-endpoint" {
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  name                = "pe-${local.suffix}"
  subnet_id           = data.azurerm_subnet.snet-sql.id

  private_service_connection {
    name                           = "private-service-connection"
    private_connection_resource_id = azurerm_mssql_server.sql.id
    is_manual_connection           = false
    subresource_names              = ["sqlserver"]
  }

  depends_on = [
    module.vnet
  ]
}

data "azurerm_private_endpoint_connection" "private-endpoint-connection" {
  resource_group_name = azurerm_resource_group.rg.name
  name                = azurerm_private_endpoint.sql-private-endpoint.name

  depends_on = [
    azurerm_private_endpoint.sql-private-endpoint
  ]
}

resource "azurerm_private_dns_zone" "private-dns-zone" {
  resource_group_name = azurerm_resource_group.rg.name
  name                = "privatelink.database.windows.net"
}

resource "azurerm_private_dns_a_record" "private-dns-a-record" {
  resource_group_name = azurerm_resource_group.rg.name
  name                = lower(azurerm_mssql_server.sql.name)
  zone_name           = azurerm_private_dns_zone.private-dns-zone.name
  ttl                 = 300
  records             = [data.azurerm_private_endpoint_connection.private-endpoint-connection.private_service_connection.0.private_ip_address]
}

resource "azurerm_private_dns_zone_virtual_network_link" "private-dns-zone-vnet-link" {
  resource_group_name   = azurerm_resource_group.rg.name
  name                  = "${azurerm_private_dns_zone.private-dns-zone.name}-link"
  private_dns_zone_name = azurerm_private_dns_zone.private-dns-zone.name
  virtual_network_id    = data.azurerm_virtual_network.vnet.id
}

##################################################################################
# LOCAL FILE
##################################################################################



##################################################################################
# OUTPUT
##################################################################################
