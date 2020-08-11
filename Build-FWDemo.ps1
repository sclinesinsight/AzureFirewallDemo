# Script to build the Azure Firewall environment per the following tutorial https://docs.microsoft.com/en-us/azure/firewall/tutorial-hybrid-portal
#
#
Write-Host "This script will build a demo environment for Azure Firewall"
Write-Host "Log into your Azure subscription"
Login-AzAccount 
#
#Build the Resource Group
$rg = read-host "Enter the resource group name: "
$location = read-host "Enter the Azure region: "
new-azresourcegroup -name $rg -location $location
#
#Build the Virtual Networks
#Build the Hub VNet
$hubVnet = New-AzVirtualNetwork -resourcegroupname $rg -location $location -name "Vnet-hub" -AddressPrefix 10.5.0.0/16
$subnetConfig1 = Add-AzVirtualNetworkSubnetConfig -Name "AzureFirewallSubnet" -AddressPrefix 10.5.0.0/26 -VirtualNetwork $hubVnet
$hubVNet | Set-AzVirtualNetwork
$hubVnet = get-azvirtualnetwork -ResourceGroupName $rg -name "Vnet-Hub"
$vpnsubnetconfig1 = Add-AzVirtualNetworkSubnetConfig -Name "GatewaySubnet" -AddressPrefix 10.5.1.0/24 -VirtualNetwork $hubVnet
$hubVNet | Set-AzVirtualNetwork
#
#Build the Spoke VNet
$spokeVNet = New-AzVirtualNetwork -ResourceGroupName $rg -Location $location -AddressPrefix 10.6.0.0/16 -name "VNet-Spoke"
$subnetConfig2 = Add-AzVirtualNetworkSubnetConfig -name "SN-Workload" -AddressPrefix 10.6.0.0/24 -VirtualNetwork $spokeVNet
$spokeVNet | Set-AzVirtualNetwork
#
#Build the Onprem VNet
$onpremVnet = New-AzVirtualNetwork -ResourceGroupName $rg -Location $location -name "VNet-OnPrem" -AddressPrefix 192.168.0.0/16
$subnetConfig3 = Add-AzVirtualNetworkSubnetConfig -name "SN-Corp" -AddressPrefix 192.168.1.0/24 -VirtualNetwork $onpremVnet
$onpremVnet | Set-AzVirtualNetwork
$subnetConfig4 = Add-AzVirtualNetworkSubnetConfig -name "GatewaySubnet" -AddressPrefix 192.168.2.0/24 -VirtualNetwork $onpremVnet
$onpremVnet | Set-AzVirtualNetwork
#
#Build the Azure Firewall
$FWPiP = New-AzPublicIpAddress -name "fw-pip" -ResourceGroupName $rg -Location $location -AllocationMethod Static -Sku Standard
write-host "Building the Azure Firewall"
$AzFW = New-AzFirewall -name "AzFW01" -ResourceGroupName $rg -Location $location -VirtualNetworkName "Vnet-hub" -PublicIpName "fw-pip"
#
#Create network rules
$NetRule1 = New-AzFirewallNetworkRule -Name "AllowWeb" -Protocol TCP -SourceAddress 192.168.1.0/24 -DestinationAddress 10.6.0.0/16 -DestinationPort 80
$NetRule2 = New-AzFirewallNetworkRule -Name "AllowRDP" -Protocol TCP -SourceAddress 192.168.1.0/24 -DestinationAddress 10.6.0.0/16 -DestinationPort 3389
$NetRuleCollection = New-AzFirewallNetworkRuleCollection -Name RCNet01 -Priority 100 -Rule $NetRule1, $NetRule2 -ActionType "Allow"
$Azfw.NetworkRuleCollections.Add($NetRuleCollection)
Set-AzFirewall -AzureFirewall $Azfw
#
#Build VPN Gateway for hub vnet
$gwpip = New-AzPublicIpAddress -name "VNet-hub-GW-pip" -ResourceGroupName $rg -Location $location -AllocationMethod Dynamic 
$hubVnet = get-azvirtualnetwork -ResourceGroupName $rg -name "Vnet-Hub"
$vpnsubnetconfig1 = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $hubVnet -name "GatewaySubnet"
$gwipconfig = New-AZVirtualNetworkGatewayIpConfig -name "gwipconfig1" -subnetid $vpnsubnetconfig1.id -publicIpaddressId $gwpip.id
write-host "Building the VPN GW for the Hub vnet. This will take a while"
$vpnHubGW = New-AzVirtualNetworkGateway -name "GW-hub" -resourcegroupname $rg -location $location -ipconfigurations $gwipconfig -gatewaytype VPN -vpntype routebased -gatewaysku Basic
#
#Build VPN Gateway for onprem vnet
$gwpip = New-AzPublicIpAddress -name "VNet-onprem-GW-pip" -ResourceGroupName $rg -Location $location -AllocationMethod Dynamic 
$onpremVnet = get-azvirtualnetwork -ResourceGroupName $rg -name "Vnet-Onprem"
$subnetConfig4 = Get-AzVirtualNetworkSubnetConfig -virtualnetwork $onpremVnet -name "GatewaySubnet"
$gwipconfig = New-AZVirtualNetworkGatewayIpConfig -name "gwipconfig2" -subnetid $subnetConfig4.id -publicIpaddressId $gwpip.id
write-host "Building the VPN GW for the Onprem vnet. This will take a while"
$vpnOnpremGW = new-azvirtualnetworkgateway -name "GW-Onprem" -resourcegroupname $rg -location $location -ipconfigurations $gwipconfig -gatewaytype VPN -vpntype routebased -gatewaysku Basic
#
#Build the VPN connections
New-azvirtualnetworkgatewayconnection -name "Hub-to-Onprem" -resourcegroupname $rg -location $location -virtualNetworkGateway1 $vpnHubGW -virtualNetworkGateway2 $vpnOnpremGW -connectiontype Vnet2Vnet -Sharedkey "AzureA1b2C3"
New-azvirtualnetworkgatewayconnection -name "Onprem-to-Hub" -resourcegroupname $rg -location $location -virtualNetworkGateway1 $vpnOnpremGW -virtualNetworkGateway2 $vpnHubGW -connectiontype Vnet2Vnet -Sharedkey "AzureA1b2C3"
#
#Peer the hub and spoke networks
add-azvirtualnetworkpeering -name "HubtoSpoke" -virtualnetwork $hubVNet -RemoteVirtualNetworkId $onpremVnet.id -allowgatewaytransit
add-azvirtualnetworkpeering -name "HubtoSpoke" -virtualnetwork $onpremVNet -RemoteVirtualNetworkId $hubVnet.id -allowforwardedtraffic
#
#Create network routes
#Route for Hub vnet to route to spoke via the firewall
$azfw = Get-AzFirewall -name "AzFW01" -ResourceGroupName $rg
$toSpokeRoute = New-AzRouteConfig -name "ToSpoke" -AddressPrefix 10.6.0.0/16 -NextHopType VirtualAppliance -NextHopIpAddress $azfw.ipconfigurations.privateipaddress
$toSpokeRouteTable = New-AzRouteTable -name "UDR-Hub-Spoke" -resourcegroupname $rg -Location $location -route $toSpokeRoute
$hubVnet = get-azvirtualnetwork -ResourceGroupName $rg -name "Vnet-Hub"
$vpnsubnetconfig1 = set-AzVirtualNetworkSubnetConfig -Name "GatewaySubnet" -VirtualNetwork $hubVnet -AddressPrefix 10.5.1.0/24 -RouteTableId $toSpokeRouteTable.Id
$hubVNet | Set-AzVirtualNetwork
#Default route from spoke subnet
$fromSpokeRoute = New-AzRouteConfig -name "ToHub" -AddressPrefix 0.0.0.0/0 -NextHopType VirtualAppliance -NextHopIpAddress $azfw.ipconfigurations.privateipaddress
$fromSpokeRouteTable = New-AzRouteTable -name "UDR-DG" -ResourceGroupName $rg -Location $location -route $fromSpokeRoute
$spokeVNet = get-azvirtualnetwork -resourcegroupname $rg -name "Vnet-Spoke"
$subnetConfig2 = set-AzVirtualNetworkSubnetConfig -name "SN-Workload" -AddressPrefix 10.6.0.0/24 -VirtualNetwork $spokeVNet -RouteTableId $fromSpokeRouteTable.Id
$spokeVNet | Set-AzVirtualNetwork
#
#Build storage account for VM diags
New-AzStorageAccount -ResourceGroupName $rg -AccountName "azurefirewalldemosa" -Location $location -SkuName Standard_LRS
#
#Build workload VM
# Create user object
$cred = Get-Credential -Message "Enter a username and password for the VMs."
$vmname = "VM-Spoke-01"
$vmnic = $vmname + "-nic"
$vmnsg = $vmname + "-nsg"
# Create an inbound network security group rule for port 3389
$nsgRuleRDP = New-AzNetworkSecurityRuleConfig -Name myNetworkSecurityGroupRuleRDP  -Protocol Tcp -Direction Inbound -Priority 1000 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389 -Access Allow
$nsgRuleWeb = New-AzNetworkSecurityRuleConfig -Name myNetworkSecurityGroupRuleHTTP  -Protocol Tcp -Direction Inbound -Priority 1001 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 80 -Access Allow
# Create a network security group
$nsg = New-AzNetworkSecurityGroup -ResourceGroupName $rg -Location $location -Name $vmnsg -SecurityRules $nsgRuleRDP, $nsgRuleWeb
# Create a virtual network card and associate with public IP address and NSG
$subnetConfig2 = get-azvirtualnetworksubnetconfig -VirtualNetwork $spokeVNet -name "SN-Workload" 
$nic = New-AzNetworkInterface -Name $vmnic -ResourceGroupName $rg -Location $location -SubnetId $subnetConfig2.Id  -NetworkSecurityGroupId $nsg.Id
# Create a virtual machine configuration
$vmConfig = New-AzVMConfig -VMName $vmname -VMSize Standard_D1 | Set-AzVMOperatingSystem -Windows -ComputerName $vmName -Credential $cred | Set-AzVMSourceImage -PublisherName MicrosoftWindowsServer -Offer WindowsServer -Skus 2016-Datacenter -Version latest | Add-AzVMNetworkInterface -Id $nic.Id
# Create a virtual machine
New-AzVM -ResourceGroupName $rg -Location $location -VM $vmConfig
#
#Build onprem VM
$vmname = "VM-Onprem"
$vmnic = $vmname + "-nic"
$vmnsg = $vmname + "-nsg"
# Create an inbound network security group rule for port 3389
$nsgRuleRDP = New-AzNetworkSecurityRuleConfig -Name myNetworkSecurityGroupRuleRDP  -Protocol Tcp -Direction Inbound -Priority 1000 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389 -Access Allow
# Create a network security group
$nsg = New-AzNetworkSecurityGroup -ResourceGroupName $rg -Location $location -Name $vmnsg -SecurityRules $nsgRuleRDP
# Create a virtual network card and associate with public IP address and NSG
$subnetConfig3 = Get-AzVirtualNetworkSubnetConfig -virtualnetwork $onpremVnet -name "SN-Corp"
$nic = New-AzNetworkInterface -Name $vmnic -ResourceGroupName $rg -Location $location -SubnetId $subnetConfig3.Id  -NetworkSecurityGroupId $nsg.Id
# Create a virtual machine configuration
$vmConfig = New-AzVMConfig -VMName $vmname -VMSize Standard_D1 | Set-AzVMOperatingSystem -Windows -ComputerName $vmName -Credential $cred | Set-AzVMSourceImage -PublisherName MicrosoftWindowsServer -Offer WindowsServer -Skus 2016-Datacenter -Version latest | Add-AzVMNetworkInterface -Id $nic.Id
# Create a virtual machine
New-AzVM -ResourceGroupName $rg -Location $location -VM $vmConfig
#
#Install IIS on the workload VM
Set-AzVMExtension -ResourceGroupName $rg -ExtensionName IIS -VMName "VM-Spoke-01" -Publisher Microsoft.Compute -ExtensionType CustomScriptExtension -TypeHandlerVersion 1.4 -SettingString '{"commandToExecute":"powershell Add-WindowsFeature Web-Server; powershell      Add-Content -Path \"C:\\inetpub\\wwwroot\\Default.htm\" -Value $($env:computername)"}' -Location $location
