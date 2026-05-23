# terraform.tfvars (SAFE TO COMMIT TO GIT)
resource_group_name   = "rg-corp-network-dev"
location              = "centralus"
prefix                = "corp"
environment           = "prod" # Change to prod since your YAML targets the production environment

subnets = {
  web                 = "10.10.1.0/24"
  app                 = "10.10.2.0/24"
  db                  = "10.10.3.0/24"
  pe                  = "10.10.4.0/24"
  gateway             = "10.10.255.224/27"
  AzureBastionSubnet  = "10.10.254.0/26"
  AzureFirewallSubnet = "10.10.253.0/26"
  secondary           = "10.20.1.0/24"
}

deploy_vpn               = true
deploy_bastion           = true
deploy_firewall          = true
deploy_log_analytics     = true
deploy_key_vault         = true
deploy_private_endpoints = true

# DO NOT PUT THE VPN CERT HERE!
# vpn_root_cert_data     = "..." 