param(
    $TenantId,
    $ResourceGroup,
    $WebAppName
)

Install-Module AzureAD
#$TenantId="<TENANT-ID>"
#$ResourceGroup = "{SCEPMAN AZURE WEB APP RESOURCE GROUP}"
#$WebAppName="{SCEPMAN AZURE WEB APP NAME}"
$ServicePrincipalId = (Get-AzWebApp -ResourceGroupName $ResourceGroup -Name $WebAppName).Identity.PrincipalId
$PermissionName = "SCEP_CHALLENGE_PROVIDER"
Connect-AzureAd -TenantId $TenantId
$IntuneServicePrincipal = Get-AzureAdServicePrincipal -SearchString "Microsoft Intune API" | Select-Object First 1
$AppRole = $IntuneServicePrincipal.AppRoles | Where-Object {$_.Value -eq $PermissionName -and $_.AllowedMemberTypes -contains "Application"}
New-AzureAdServiceAppRoleAssignment -ObjectId $ServicePrincipalId -PrincipalId $ServicePrincipalId -ResourceId $IntuneServicePrincipal.ObjectId -Id $AppRole.Id
