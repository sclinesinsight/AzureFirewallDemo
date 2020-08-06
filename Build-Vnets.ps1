$resourceGroupName = Read-Host -Prompt "Enter the Resource Group name"
Write-host "RG is " $resourceGroupName
$location = Read-Host -Prompt "Enter the location (i.e. centralus)"
Write-host "Location is " $location
# Build Resource Group
New-azresourcegroup -name $resourcegroupname -location $location
# Issue ARM template for Vnet deployment
$templateUri = "https://raw.githubusercontent.com/sclinesinsight/AzureFirewallDemo/master/vnets-template.json"
$parameterUri = "https://raw.githubusercontent.com/sclinesinsight/AzureFirewallDemo/master/vnets-parameters.json"
New-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -TemplateUri $templateUri -TemplateParameterUri $parameterUri
