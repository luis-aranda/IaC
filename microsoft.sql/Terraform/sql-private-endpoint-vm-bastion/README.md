# Deploy an Azure SQL Server with Private Endpoint enabled along with an Azure VM with bastion

This template allows you to deploy an Azure SQL server with a private endpoint enabled

It also deploys an Azure VM and also a Bastion host that allow to connect securely

The VNET in this template will be provisioned with 3 different subnets, one for each type of resource (Bastion, VM and SQL)