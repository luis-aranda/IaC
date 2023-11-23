$newAzSqlDatabaseInstanceFailoverGroupSplat = @{
    Name                         = 'mifog-cus'
    Location                     = 'CentralUS'
    ResourceGroupName            = 'rg-sqlmifog-cus'
    PrimaryManagedInstanceName   = 'lacsqlmicus'
    PartnerRegion                = 'WestUS3'
    PartnerManagedInstanceName   = 'lacsqlmiwus'
    PartnerResourceGroupName     = 'rg-sqlmifog-cus'
    FailoverPolicy               = 'Automatic'
    GracePeriodWithDataLossHours = 1
}

New-AzSqlDatabaseInstanceFailoverGroup @newAzSqlDatabaseInstanceFailoverGroupSplat 