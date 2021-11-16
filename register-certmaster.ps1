Connect-AzureAD

$certMasterBaseURL = "https://as-certmaster-askjvljweklraesr.azurewebsites.net"
 
$reg = New-AzureADApplication -DisplayName "CertMaster v2.0" -ReplyUrls "$certMasterBaseURL/signin-oidc" -LogoutUrl "$certMasterBaseURL/signout-callback-oidc"

