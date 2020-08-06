$resourceGroupName = Read-Host -Prompt "Enter the Resource Group name"
$location = Read-Host -Prompt "Enter the location (i.e. centralus)"
$templateUri = "https://github.com/sclinesinsight/AzureFirewallDemo/blob/master/vnets-template.json"
$parameterUri = "https://github.com/sclinesinsight/AzureFirewallDemo/blob/master/vnets-parameters.json"
New-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -TemplateUri $templateUri -Location $location -TemplateParameterUri $parameterUri
