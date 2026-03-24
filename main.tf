provider "azurerm" {
features {}
subscription_id = var.F-SubscriptionID
}


#variables
variable "A-location" {
    description = "Location of the resources, example: eastus2"
    
    
}

variable "B-resource_group_name" {
    description = "Name of the resource group to create"
    
}



variable "D-username" {
    description = "Username for Virtual Machines"
    
}

variable "E-password" {
    description = "Password for Virtual Machines"
    sensitive = true
    
}

variable "F-SubscriptionID" {
  description = "Subscription ID to use"
  
}

resource "azurerm_resource_group" "RG" {
  location = var.A-location
  name     = var.B-resource_group_name
}

#logic app to self destruct resourcegroup after 24hrs
data "azurerm_subscription" "sub" {
}

resource "azurerm_logic_app_workflow" "workflow1" {
  location = azurerm_resource_group.RG.location
  name     = "labdelete"
  resource_group_name = azurerm_resource_group.RG.name
  identity {
    type = "SystemAssigned"
  }
  depends_on = [
    azurerm_resource_group.RG,
  ]
}
resource "azurerm_role_assignment" "contrib1" {
  scope = azurerm_resource_group.RG.id
  role_definition_name = "Contributor"
  principal_id  = azurerm_logic_app_workflow.workflow1.identity[0].principal_id
  depends_on = [azurerm_logic_app_workflow.workflow1]
}


resource "azurerm_resource_group_template_deployment" "apiconnections" {
  name                = "group-deploy"
  resource_group_name = azurerm_resource_group.RG.name
  deployment_mode     = "Incremental"
  template_content = <<TEMPLATE
{
    "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {},
    "variables": {},
    "resources": [
        {
            "type": "Microsoft.Web/connections",
            "apiVersion": "2016-06-01",
            "name": "arm-1",
            "location": "${azurerm_resource_group.RG.location}",
            "kind": "V1",
            "properties": {
                "displayName": "labdeleteconn1",
                "authenticatedUser": {},
                "statuses": [
                    {
                        "status": "Ready"
                    }
                ],
                "connectionState": "Enabled",
                "customParameterValues": {},
                "alternativeParameterValues": {},
                "parameterValueType": "Alternative",
                "createdTime": "2023-05-21T23:07:20.1346918Z",
                "changedTime": "2023-05-21T23:07:20.1346918Z",
                "api": {
                    "name": "arm",
                    "displayName": "Azure Resource Manager",
                    "description": "Azure Resource Manager exposes the APIs to manage all of your Azure resources.",
                    "iconUri": "https://connectoricons-prod.azureedge.net/laborbol/fixes/path-traversal/1.0.1552.2695/arm/icon.png",
                    "brandColor": "#003056",
                    "id": "/subscriptions/${data.azurerm_subscription.sub.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.RG.location}/managedApis/arm",
                    "type": "Microsoft.Web/locations/managedApis"
                },
                "testLinks": []
            }
        },
        {
            "type": "Microsoft.Logic/workflows",
            "apiVersion": "2017-07-01",
            "name": "labdelete",
            "location": "${azurerm_resource_group.RG.location}",
            "dependsOn": [
                "[resourceId('Microsoft.Web/connections', 'arm-1')]"
            ],
            "identity": {
                "type": "SystemAssigned"
            },
            "properties": {
                "state": "Enabled",
                "definition": {
                    "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
                    "contentVersion": "1.0.0.0",
                    "parameters": {
                        "$connections": {
                            "defaultValue": {},
                            "type": "Object"
                        }
                    },
                    "triggers": {
                        "Recurrence": {
                            "recurrence": {
                                "frequency": "Minute",
                                "interval": 3,
                                "startTime": "${timeadd(timestamp(),"24h")}"
                            },
                            "evaluatedRecurrence": {
                                "frequency": "Minute",
                                "interval": 3,
                                "startTime": "${timeadd(timestamp(),"24h")}"
                            },
                            "type": "Recurrence"
                        }
                    },
                    "actions": {
                        "Delete_a_resource_group": {
                            "runAfter": {},
                            "type": "ApiConnection",
                            "inputs": {
                                "host": {
                                    "connection": {
                                        "name": "@parameters('$connections')['arm']['connectionId']"
                                    }
                                },
                                "method": "delete",
                                "path": "/subscriptions/@{encodeURIComponent('${data.azurerm_subscription.sub.subscription_id}')}/resourcegroups/@{encodeURIComponent('${azurerm_resource_group.RG.name}')}",
                                "queries": {
                                    "x-ms-api-version": "2016-06-01"
                                }
                            }
                        }
                    },
                    "outputs": {}
                },
                "parameters": {
                    "$connections": {
                        "value": {
                            "arm": {
                                "connectionId": "[resourceId('Microsoft.Web/connections', 'arm-1')]",
                                "connectionName": "arm-1",
                                "connectionProperties": {
                                    "authentication": {
                                        "type": "ManagedServiceIdentity"
                                    }
                                },
                                "id": "/subscriptions/${data.azurerm_subscription.sub.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.RG.location}/managedApis/arm"
                            }
                        }
                    }
                }
            }
        }
    ]
}
TEMPLATE
}

resource "random_pet" "name" {
  length = 1
}

#log analytics workspace
resource "azurerm_log_analytics_workspace" "LAW" {
  name                = "LAW-${random_pet.name.id}"
  location            = azurerm_resource_group.RG.location
  resource_group_name = azurerm_resource_group.RG.name
  
}


#vnets and subnets
resource "azurerm_virtual_network" "hub-vnet" {
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.RG.location
  name                = "AZ-hub-vnet"
  resource_group_name = azurerm_resource_group.RG.name
  subnet {
    address_prefixes     = ["10.0.0.0/24"]
    name                 = "default"
    security_group = azurerm_network_security_group.hubvnetNSG.id
    default_outbound_access_enabled = false
  }
  subnet {
    address_prefixes     = ["10.0.1.0/24"]
    name                 = "GatewaySubnet"
    default_outbound_access_enabled = false 
  }
  subnet {
    address_prefixes     = ["10.0.2.0/24"]
    name                 = "AzureFirewallSubnet"
    default_outbound_access_enabled = false 
  }
  subnet {
    address_prefixes     = ["10.0.3.0/24"]
    name                 = "AzureFirewallManagementSubnet"
    default_outbound_access_enabled = false 
  }
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}


resource "azurerm_virtual_network" "spoke1-vnet" {
  address_space       = ["10.150.0.0/16"]
  location            = azurerm_resource_group.RG.location
  name                = "AZ-spoke1-vnet"
  resource_group_name = azurerm_resource_group.RG.name
  subnet {
    address_prefixes     = ["10.150.0.0/24"]
    name                 = "default"
    security_group = azurerm_network_security_group.spokevnetNSG.id
    default_outbound_access_enabled = false
  }
  subnet {
    address_prefixes     = ["10.150.1.0/24"]
    name                 = "GatewaySubnet" 
    default_outbound_access_enabled = false
  }
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}
resource "azurerm_virtual_network" "spoke2-vnet" {
  address_space       = ["10.250.0.0/16"]
  location            = azurerm_resource_group.RG.location
  name                = "AZ-spoke2-vnet"
  resource_group_name = azurerm_resource_group.RG.name
  subnet {
    address_prefixes     = ["10.250.0.0/24"]
    name                 = "default"
    security_group = azurerm_network_security_group.spokevnetNSG.id
    default_outbound_access_enabled = false
  }
  subnet {
    address_prefixes     = ["10.250.1.0/24"]
    name                 = "GatewaySubnet" 
    default_outbound_access_enabled = false
  }
  subnet {
    address_prefixes     = ["10.250.2.0/24"]
    name                 = "AzureBastionSubnet" 
    default_outbound_access_enabled = false
  }
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}


resource "azurerm_virtual_network_peering" "hubtospoke1peering" {
  name                      = "hub-to-spoke1-peering"
  remote_virtual_network_id = azurerm_virtual_network.spoke1-vnet.id
  resource_group_name       = azurerm_resource_group.RG.name
  virtual_network_name      = "AZ-hub-vnet"
  allow_forwarded_traffic = true
  allow_gateway_transit = true
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  depends_on = [
    azurerm_virtual_network.hub-vnet,
    azurerm_virtual_network.spoke1-vnet,
    
  ]
}
resource "azurerm_virtual_network_peering" "hubtospoke2peering" {
  name                      = "hub-to-spoke2-peering"
  remote_virtual_network_id = azurerm_virtual_network.spoke2-vnet.id
  resource_group_name       = azurerm_resource_group.RG.name
  virtual_network_name      = "AZ-hub-vnet"
  allow_forwarded_traffic = true
  allow_gateway_transit = true
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  depends_on = [
    azurerm_virtual_network.hub-vnet,
    azurerm_virtual_network.spoke2-vnet,
    
  ]
}
resource "azurerm_virtual_network_peering" "spoke1tohubpeering" {
  name                      = "spoke1-to-hub-peering"
  remote_virtual_network_id = azurerm_virtual_network.hub-vnet.id
  resource_group_name       = azurerm_resource_group.RG.name
  virtual_network_name      = "AZ-spoke1-vnet"
  allow_forwarded_traffic = true
  
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  depends_on = [
    azurerm_virtual_network.spoke1-vnet,
    azurerm_virtual_network.hub-vnet,
    
  ]
}
resource "azurerm_virtual_network_peering" "spoke2tohubpeering" {
  name                      = "spoke2-to-hub-peering"
  remote_virtual_network_id = azurerm_virtual_network.hub-vnet.id
  resource_group_name       = azurerm_resource_group.RG.name
  virtual_network_name      = "AZ-spoke2-vnet"
  allow_forwarded_traffic = true
  
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  depends_on = [
    azurerm_virtual_network.spoke2-vnet,
    azurerm_virtual_network.hub-vnet,
    
  ]
}

#route table
resource "azurerm_route_table" "RT1" {
  name                          = "spoke1UDR"
  location                      = azurerm_resource_group.RG.location
  resource_group_name           = azurerm_resource_group.RG.name
  

  route {
    name           = "inet"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "VirtualAppliance"
    next_hop_in_ip_address = "10.0.2.4"
  }
  
  route {
    name           = "tospoke2"
    address_prefix = "10.250.0.0/16"
    next_hop_type  = "VirtualAppliance"
    next_hop_in_ip_address = "10.0.2.4"
  }
  route {
    name           = "tohub"
    address_prefix = "10.0.0.0/24"
    next_hop_type  = "VirtualAppliance"
    next_hop_in_ip_address = "10.0.2.4"
  }
  route {
    name           = "tohome"
    address_prefix = "73.232.172.101/32"
    next_hop_type  = "Internet"
    
  }  
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
}
resource "azurerm_route_table" "RT2" {
  name                          = "spoke2UDR"
  location                      = azurerm_resource_group.RG.location
  resource_group_name           = azurerm_resource_group.RG.name
  

  route {
    name           = "inet"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "VirtualAppliance"
    next_hop_in_ip_address = "10.0.2.4"
  }
  route {
    name           = "tospoke1"
    address_prefix = "10.150.0.0/16"
    next_hop_type  = "VirtualAppliance"
    next_hop_in_ip_address = "10.0.2.4"
  }
  route {
    name           = "tohub"
    address_prefix = "10.0.0.0/24"
    next_hop_type  = "VirtualAppliance"
    next_hop_in_ip_address = "10.0.2.4"
  }  
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
}
resource "azurerm_route_table" "RT3" {
  name                          = "hubUDR"
  location                      = azurerm_resource_group.RG.location
  resource_group_name           = azurerm_resource_group.RG.name
  

  route {
    name           = "inet"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "VirtualAppliance"
    next_hop_in_ip_address = "10.0.2.4"
  }
  route {
    name           = "tospoke1"
    address_prefix = "10.150.0.0/16"
    next_hop_type  = "VirtualAppliance"
    next_hop_in_ip_address = "10.0.2.4"
  }
  route {
    name           = "tospoke2"
    address_prefix = "10.250.0.0/16"
    next_hop_type  = "VirtualAppliance"
    next_hop_in_ip_address = "10.0.2.4"
  }  
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
}


resource "azurerm_subnet_route_table_association" "onhubdefaultsubnet" {
  subnet_id      = azurerm_virtual_network.hub-vnet.subnet.*.id[0]
  route_table_id = azurerm_route_table.RT3.id
  timeouts {
    create = "2h"
    read = "2h"
    
    delete = "2h"
  }
}
resource "azurerm_subnet_route_table_association" "onspoke1defaultsubnet" {
  subnet_id      = azurerm_virtual_network.spoke1-vnet.subnet.*.id[0]
  route_table_id = azurerm_route_table.RT1.id
  timeouts {
    create = "2h"
    read = "2h"
    
    delete = "2h"
  }
}
resource "azurerm_subnet_route_table_association" "onspoke2defaultsubnet" {
  subnet_id      = azurerm_virtual_network.spoke2-vnet.subnet.*.id[0]
  route_table_id = azurerm_route_table.RT2.id
  timeouts {
    create = "2h"
    read = "2h"
    
    delete = "2h"
  }
}

#NSG's
resource "azurerm_network_security_group" "hubvnetNSG" {
  location            = azurerm_resource_group.RG.location
  name                = "AZ-hub-vnet-default-nsg"
  resource_group_name = azurerm_resource_group.RG.name
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}

resource "azurerm_network_security_group" "spokevnetNSG" {
  location            = azurerm_resource_group.RG.location
  name                = "AZ-spoke-vnet-default-nsg"
  resource_group_name = azurerm_resource_group.RG.name
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}



#Public IP's

resource "azurerm_public_ip" "natgw-pip" {
  name                = "natgw-pip"
  location            = azurerm_resource_group.RG.location
  resource_group_name = azurerm_resource_group.RG.name
  allocation_method = "Static"
  sku = "Standard"
  
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}
resource "azurerm_public_ip" "azfwmgt-pip" {
  name                = "azfw-mgt-pip"
  location            = azurerm_resource_group.RG.location
  resource_group_name = azurerm_resource_group.RG.name
  allocation_method = "Static"
  sku = "Standard"
  
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}



#Azfirewall and policy
resource "azurerm_firewall_policy" "azfwpolicy" {
  name                = "azfw-policy"
  resource_group_name = azurerm_resource_group.RG.name
  location            = azurerm_resource_group.RG.location
  sku = "Basic"
  
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
}
resource "azurerm_firewall_policy_rule_collection_group" "azfwpolicyrcg" {
  name               = "azfwpolicy-rcg"
  firewall_policy_id = azurerm_firewall_policy.azfwpolicy.id
  priority           = 500
  network_rule_collection {
    name     = "network_rule_collection1"
    priority = 400
    action   = "Allow"
    rule {
      name                  = "network_rule_collection1_rule1"
      protocols             = ["Any"]
      source_addresses      = ["10.150.0.0/16"]
      destination_addresses = ["*"]
      destination_ports     = ["*"]
    }
  }
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
    }
  
}
resource "azurerm_firewall" "azfw" {
  name                = "AzureFirewall"
  location            = azurerm_resource_group.RG.location
  resource_group_name = azurerm_resource_group.RG.name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Basic"
  firewall_policy_id = azurerm_firewall_policy.azfwpolicy.id

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_virtual_network.hub-vnet.subnet.*.id[2]
    
  }
  management_ip_configuration {
    name                 = "management-configuration"
    subnet_id            = azurerm_virtual_network.hub-vnet.subnet.*.id[3]
    public_ip_address_id = azurerm_public_ip.azfwmgt-pip.id
  }
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}
#firewall logging
resource "azurerm_monitor_diagnostic_setting" "fwlogs"{
  name = "fwlogs-${random_pet.name.id}"
  target_resource_id = azurerm_firewall.azfw.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.LAW.id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category = "AZFWNetworkRule"
  }
  enabled_log {
    category = "AZFWApplicationRule"
  }
  enabled_log {
    category = "AZFWNatRule"
  }
  enabled_log {
    category = "AZFWThreatIntel"
  }
  enabled_log {
    category = "AZFWIdpsSignature"
  }
  enabled_log {
    category = "AZFWDnsQuery"
  }
  enabled_log {
    category = "AZFWFqdnResolveFailure"
  }
  enabled_log {
    category = "AZFWFatFlow"
  }
  enabled_log {
    category = "AZFWFlowTrace"
  }
}

#natgw
resource "azurerm_nat_gateway" "natgw" {
  name                = "NatGateway"
  location            = azurerm_resource_group.RG.location
  resource_group_name = azurerm_resource_group.RG.name
  sku_name            = "Standard"
}

resource "azurerm_nat_gateway_public_ip_association" "natgwip" {
  nat_gateway_id       = azurerm_nat_gateway.natgw.id
  public_ip_address_id = azurerm_public_ip.natgw-pip.id
}

resource "azurerm_subnet_nat_gateway_association" "azfwnatgw" {
  subnet_id      = azurerm_virtual_network.hub-vnet.subnet.*.id[2]
  nat_gateway_id = azurerm_nat_gateway.natgw.id
}



#vNIC's
resource "azurerm_network_interface" "hubvm-nic" {
  location            = azurerm_resource_group.RG.location
  name                = "hubvm-nic"
  resource_group_name = azurerm_resource_group.RG.name
  ip_configuration {
    name                          = "ipconfig1"
    private_ip_address_allocation = "Dynamic"
    
    subnet_id                     = azurerm_virtual_network.hub-vnet.subnet.*.id[0]
  }
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}
resource "azurerm_network_interface" "spoke1vm-nic" {
  location            = azurerm_resource_group.RG.location
  name                = "spoke1vm-nic"
  resource_group_name = azurerm_resource_group.RG.name
  ip_configuration {
    name                          = "ipconfig1"
    private_ip_address_allocation = "Dynamic"
    
    subnet_id                     = azurerm_virtual_network.spoke1-vnet.subnet.*.id[0]
  }
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}
resource "azurerm_network_interface" "spoke2vm-nic" {
  location            = azurerm_resource_group.RG.location
  name                = "spoke2vm-nic"
  resource_group_name = azurerm_resource_group.RG.name
  ip_configuration {
    name                          = "ipconfig1"
    private_ip_address_allocation = "Dynamic"
    
    subnet_id                     = azurerm_virtual_network.spoke2-vnet.subnet.*.id[0]
  }
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}


resource "azurerm_linux_virtual_machine" "spoke1vm" {
  name                  = "spoke1vm"
  location              = azurerm_resource_group.RG.location
  resource_group_name   = azurerm_resource_group.RG.name
  network_interface_ids = [azurerm_network_interface.spoke1vm-nic.id]
  size                  = "Standard_B2ms"

  os_disk {    
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  admin_username                  = var.D-username
  admin_password                  = var.E-password
  disable_password_authentication = false
  boot_diagnostics {storage_account_uri = ""}
}




resource "azurerm_linux_virtual_machine" "hubvm" {
  admin_password        = var.E-password
  admin_username        = var.D-username
  location              = azurerm_resource_group.RG.location
  name                  = "hubvm"
  network_interface_ids = [azurerm_network_interface.hubvm-nic.id]
  resource_group_name   = azurerm_resource_group.RG.name
  size                  = "Standard_B2ms"
  
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
  boot_diagnostics {storage_account_uri = ""}
  disable_password_authentication = false
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}



resource "azurerm_linux_virtual_machine" "spoke2vm" {
  admin_password        = var.E-password
  admin_username        = var.D-username
  location              = azurerm_resource_group.RG.location
  name                  = "spoke2vm"
  network_interface_ids = [azurerm_network_interface.spoke2vm-nic.id]
  resource_group_name   = azurerm_resource_group.RG.name
  size                  = "Standard_B2ms"
  
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
  boot_diagnostics {storage_account_uri = ""}
  disable_password_authentication = false
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}
