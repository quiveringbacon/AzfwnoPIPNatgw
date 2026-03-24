# Azfw no PIP with Natgw

An example of how you can setup Azure firewall with no public ip but use NAT gateway for outbound internet access to get more SNAT ports.
This creates a hub vnet with 2 spoke vnets with VM's peered to the vhub vnet. It creates a NAT gateway and Azure firewall in the hub vnet, but the firewall has no public ip and will use the NAT gateway for internet egress. You'll be prompted for the resource group name, location where you want the resources created, and username and password to use for the VM's. . This also creates a logic app that will delete the resource group in 24hrs.

The topology will look like this:

<img width="755" height="337" alt="natgw" src="https://github.com/user-attachments/assets/b347ca84-cc93-4419-b8b7-fae34372de45" />

You can run Terraform right from the Azure cloud shell by cloning this git repository with "git clone https://github.com/quiveringbacon/AzfwnoPIPNatgw.git ./terraform".
