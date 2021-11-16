Connect-AzureAD

$certMasterBaseURL = "https://as-certmaster-askjvljweklraesr.azurewebsites.net"

$wellKnownGuidGraphApi = "00000003-0000-0000-c000-000000000000"

# Add Directory.Read.All access
$svcPrincipal = Get-AzureADServicePrincipal -All $true | ? { $_.AppId -eq $wellKnownGuidGraphApi }
$appRole = $svcPrincipal.Oauth2Permissions | ? { $_.Value -eq "Directory.Read.All" }
$appPermission = New-Object -TypeName "Microsoft.Open.AzureAD.Model.ResourceAccess" -ArgumentList $appRole.Id, "Scope"

$reqGraph = New-Object -TypeName "Microsoft.Open.AzureAD.Model.RequiredResourceAccess"
$reqGraph.ResourceAppId = $wellKnownGuidGraphApi
$reqGraph.ResourceAccess = $appPermission


$application = New-AzureADApplication -DisplayName "CertMaster v2.0" -ReplyUrls "$certMasterBaseURL/signin-oidc" -LogoutUrl "$certMasterBaseURL/signout-callback-oidc" -RequiredResourceAccess $reqGraph

