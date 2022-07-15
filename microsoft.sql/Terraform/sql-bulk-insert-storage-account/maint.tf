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
    key                  = "bulkinsert.tfstate"
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
    "Brazil South", "Brazil Southeast", "Central US", "East US", "East US 2", "North Central US", "South Central US", "West Central US", "West US", "West US 2", "West US 3"], var.location)
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
    "West US 3"        = "wu3"
  }
}

variable "st_account_replication_type" {
  type    = string
  default = "LRS"
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.st_account_replication_type)
    error_message = "Argument 'sku_name' must be one of 'GP_Gen5' or 'BC_Gen5'."
  }
}

variable "admin_login" {
  type = string
}

variable "admin_objectid" {
  type = string
}

variable "admin_tenantid" {
  type = string
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
  st_suffix = replace(local.suffix, "-", "")
}

##################################################################################
# RESOURCES
##################################################################################
data "azurerm_key_vault" "kv" {
  name                = var.kv_name
  resource_group_name = var.kv_rg_name
}

data "azurerm_key_vault_secret" "kv_secret_username" {
  name         = "managedSqlUsernameKey"
  key_vault_id = data.azurerm_key_vault.kv.id
}

data "azurerm_key_vault_secret" "kv_secret_password" {
  name         = "managedSqlPasswordKey"
  key_vault_id = data.azurerm_key_vault.kv.id
}

data "http" "publicip" {
  url = "https://ifconfig.me"
}

resource "random_integer" "sa_num" {
  min = 10
  max = 99
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-${local.suffix}"
  location = var.location
  tags = {
    environment = terraform.workspace
  }
}

resource "azurerm_storage_account" "st" {
  name                     = "st${local.st_suffix}${random_integer.sa_num.result}"
  location                 = azurerm_resource_group.rg.location
  resource_group_name      = azurerm_resource_group.rg.name
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = var.st_account_replication_type

  network_rules {
    default_action = "Deny"
    ip_rules       = ["${data.http.publicip.body}"]
  }

  tags = {
    "environment" = terraform.workspace
  }
}

resource "azurerm_storage_container" "st_container" {
  name                  = "bulkdata"
  storage_account_name  = azurerm_storage_account.st.name
  container_access_type = "private"
}

resource "azurerm_role_assignment" "st_role_assignment" {
  scope                = azurerm_storage_account.st.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.admin_objectid
}

resource "azurerm_role_assignment" "sql_msi_role_assignment" {
  scope                = azurerm_storage_account.st.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_mssql_server.sql.identity.0.principal_id
}

resource "azurerm_mssql_server" "sql" {
  name                         = "sql-${local.suffix}"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = azurerm_resource_group.rg.location
  version                      = "12.0"
  administrator_login          = data.azurerm_key_vault_secret.kv_secret_username.value
  administrator_login_password = data.azurerm_key_vault_secret.kv_secret_password.value
  identity {
    type = "SystemAssigned"
  }

  azuread_administrator {
    login_username = var.admin_login
    object_id      = var.admin_objectid
    tenant_id      = var.admin_tenantid
  }

  tags = {
    "environment" = terraform.workspace
  }
}

resource "azurerm_mssql_firewall_rule" "sql_fw_rule" {
  name             = "HomeIP"
  server_id        = azurerm_mssql_server.sql.id
  start_ip_address = data.http.publicip.body
  end_ip_address   = data.http.publicip.body
}

resource "azurerm_mssql_database" "sqldb" {
  name        = "AdventureWorksLT"
  server_id   = azurerm_mssql_server.sql.id
  sample_name = "AdventureWorksLT"
  sku_name    = "Basic"
}

resource "null_resource" "copy_dat_file" {
  provisioner "local-exec" {
    command = <<EOF
  azcopy cp https://lacsa.blob.core.windows.net/sqlbulk/store_returns_1.dat https://${azurerm_storage_account.st.name}.blob.core.windows.net/${azurerm_storage_container.st_container.name}/store_returns_1.dat
  EOF
  }
}
##################################################################################
# LOCAL FILE
##################################################################################


##################################################################################
# OUTPUT
##################################################################################
