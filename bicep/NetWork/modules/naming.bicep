param prefix string
param environment string
param location string = resourceGroup().location

var cleanLocation = replace(location, ' ', '')
var loc = substring(cleanLocation, 0, 3)
var env = substring(environment, 0, 3)

output vnet1 string = '${prefix}-${env}-vnet-hub-${loc}'
output vnet2 string = '${prefix}-${env}-vnet-spoke-${loc}'
output nsgWeb string = '${prefix}-${env}-nsg-web-${loc}'
output nsgApp string = '${prefix}-${env}-nsg-app-${loc}'
output nsgDb string = '${prefix}-${env}-nsg-db-${loc}'
output nsgSecondary string = '${prefix}-${env}-nsg-spoke-${loc}'
output privEndpoint string = '${prefix}-${env}-pe-storage-${loc}'
output vpnGw string = '${prefix}-${env}-vpngw-${loc}'
output vpnPip string = '${prefix}-${env}-pip-vpngw-${loc}'
output bastion string = '${prefix}-${env}-bas-${loc}'
output firewall string = '${prefix}-${env}-afw-${loc}'
output keyVault string = '${prefix}-${env}-kv-${loc}'
output logAnalytics string = '${prefix}-${env}-law-${loc}'
