# for testing
$env:SCEPMAN_APP_SERVICE_NAME = "as-scepman-askjvljweklraesr"
$env:CERTMASTER_APP_SERVICE_NAME = "aleen-as-certmaster-askjvljweklraesr"
$env:SCEPMAN_RESOURCE_GROUP = "rg-SCEPman"

$SCEPmanAppServiceName = $env:SCEPMAN_APP_SERVICE_NAME
$CertMasterAppServiceName = $env:CERTMASTER_APP_SERVICE_NAME
$CertMasterBaseURL = "https://$CertMasterAppServiceName.azurewebsites.net"
$SCEPmanResourceGroup = $env:SCEPMAN_RESOURCE_GROUP

### TODO: Add Scepman App Service identification


az login

# Some hard-coded definitions
$MSGraphAppId = "00000003-0000-0000-c000-000000000000"
$MSGraphDirectoryReadAllPermission = "7ab1d382-f21e-4acd-a863-ba3e13f7da61"
$MSGraphDeviceManagementReadPermission = "2f51be20-0bb4-4fed-bf7b-db946066c75e"
$MSGraphUserReadPermission = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"

# "0000000a-0000-0000-c000-000000000000" # Service Principal App Id of Intune, not required here
$IntuneAppId = "c161e42e-d4df-4a3d-9b42-e7a3c31f59d4" # Well-known App ID of the Intune API
$IntuneSCEPChallengePermission = "39d724e8-6a34-4930-9a36-364082c35716"

$MAX_RETRY_COUNT = 4  # for some operations, retry a couple of times

# Getting tenant details
$tenantlines = az account show
$tenantjson = [System.String]::Concat($tenantlines)
$tenant = ConvertFrom-Json $tenantjson

# It is intended to use for az cli add permissions and az cli add permissions admin
# $azCommand - The command to execute. 
# 
function ExecuteAzCommandRobustly($azCommand, $principalId = $null, $appRoleId = $null) {
  $azErrorCode = 1 # A number not null
  $retryCount = 0
  while ($azErrorCode -ne 0 -and $retryCount -le $MAX_RETRY_COUNT) {
    $lastAzOutput = Invoke-Expression $azCommand # the output is often empty in case of error :-(. az just writes to the console then
    $azErrorCode = $LastExitCode
    if($null -ne $appRoleId -and $azErrorCode -eq 0) {
      $appRoleAssignmentsResponse = az rest --method get --url "https://graph.microsoft.com/v1.0/servicePrincipals/$principalId/appRoleAssignments"
      $appRoleAssignmentsResponseJson = [System.String]::Concat($appRoleAssignmentsResponse)
      $appRoleAssignments = ConvertFrom-Json($appRoleAssignmentsResponseJson)
      $grantedPermission = $appRoleAssignments.value | ? { $_.appRoleId -eq $appRoleId }
      if ($null -eq $grantedPermission) {
        $azErrorCode = 999 # A number not 0
      }
    }
    if ($azErrorCode -ne 0) {
      ++$retryCount
      Write-Debug "Retry $retryCount for $azCommand"
      Start-Sleep $retryCount # Sleep for some seconds, as the grant sometimes only works after some time
    }
  }
  if ($azErrorCode -ne 0 ) {
    Write-Error "Error $azErrorCode when executing $azCommand : $lastAzOutput"
    #exit $lastAzError
  }
  else {
    return $lastAzOutput
  }
}

## Service Principal for System-assigned identity of SCEPman
$serviceprincipallinessc = az webapp identity show --name $SCEPmanAppServiceName --resource-group $SCEPmanResourceGroup
$serviceprincipaljsonsc = [System.String]::Concat($serviceprincipallinessc)
$serviceprincipalsc = ConvertFrom-Json $serviceprincipaljsonsc

$GraphEndpointForAppRoleAssignmentssc = "https://graph.microsoft.com/v1.0/servicePrincipals/$($serviceprincipalsc.principalId)/appRoleAssignments"

## Setup MS graph permissions for SCEPman
$graphResourceId = $(az ad sp list --filter "appId eq '$MSGraphAppId'" --query [0].objectId --out tsv)

# Add Microsoft Graph's Directory.Read.All as app permission for SCEPman
$bodyToAddMSGraphDirectoryReadAllPermission = "{'principalId': '$($serviceprincipalsc.principalId)','resourceId': '$graphResourceId','appRoleId':'$MSGraphDirectoryReadAllPermission'}"
az rest --method post --uri $GraphEndpointForAppRoleAssignmentssc --body $bodyToAddMSGraphDirectoryReadAllPermission --headers "Content-Type=application/json"

# Add DeviceManagementManagedDevices.Read as app permission for SCEPman
$bodyToAddMSGraphDeviceManagementReadPermission = "{'principalId': '$($serviceprincipalsc.principalId)','resourceId': '$graphResourceId','appRoleId':'$MSGraphDeviceManagementReadPermission'}"
az rest --method post --uri $GraphEndpointForAppRoleAssignmentssc --body $bodyToAddMSGraphDeviceManagementReadPermission --headers "Content-Type=application/json"

## Setup Intune permission for SCEPman
$intuneResourceId = $(az ad sp list --filter "appId eq '$IntuneAppId'" --query [0].objectId --out tsv)
$bodyToAddIntuneSCEPChallengePermission = "{'principalId': '$($serviceprincipalsc.principalId)','resourceId': '$intuneResourceId','appRoleId':'$IntuneSCEPChallengePermission'}"
az rest --method post --uri $GraphEndpointForAppRoleAssignmentssc --body $bodyToAddIntuneSCEPChallengePermission --headers "Content-Type=application/json"

## Service Principal for System-assigned identity of CertMaster
$serviceprincipallinescm = az webapp identity show --name $CertMasterAppServiceName --resource-group $SCEPmanResourceGroup
$serviceprincipaljsoncm = [System.String]::Concat($serviceprincipallinescm)
$serviceprincipalcm = ConvertFrom-Json $serviceprincipaljsoncm


### SCEPman App Registration
# JSON defining App Role that CertMaster uses to authenticate against SCEPman
$ScepmanManifest = '[{ 
    \"allowedMemberTypes\": [
      \"Application\"
    ],
    \"description\": \"Request certificates via the raw CSR API\",
    \"displayName\": \"CSR Requesters\",
    \"isEnabled\": \"true\",
    \"value\": \"CSR.Request\"
}]'.Replace("`r", [String]::Empty).Replace("`n", [String]::Empty)

# Register SCEPman App
$appreglinessc = ExecuteAzCommandRobustly -azCommand "az ad app create --display-name SCEPman-xyz3 --app-roles '$ScepmanManifest'"
$appregjsonsc = [System.String]::Concat($appreglinessc)
$appregsc = ConvertFrom-Json $appregjsonsc

$splinessc = ExecuteAzCommandRobustly -azCommand "az ad sp create --id $($appregsc.appId)"
$spjsonsc = [System.String]::Concat($splinessc)
$spsc = ConvertFrom-Json $spjsonsc

$ScepManSubmitCSRPermission = $appregsc.appRoles[0].id

# Expose SCEPman API
az ad app update --id $appregsc.appId --identifier-uris "api://$($appregsc.appId)"

# Allow CertMaster to submit CSR requests to SCEPman API
$GraphEndpointForAppRoleAssignmentscm = "https://graph.microsoft.com/v1.0/servicePrincipals/$($serviceprincipalcm.principalId)/appRoleAssignments"

$bodyToAddSCEPmanAPIPermission = "{'principalId': '$($serviceprincipalcm.principalId)','resourceId': '$($spsc.objectId)','appRoleId':'$ScepManSubmitCSRPermission'}"
az rest --method post --uri $GraphEndpointForAppRoleAssignmentscm --body $bodyToAddSCEPmanAPIPermission --headers "Content-Type=application/json"


### CertMaster App Registration
# JSON defining App Role that User can have to when authenticating against CertMaster
$CertmasterManifest = '[{ 
    \"allowedMemberTypes\": [
      \"User\"
    ],
    \"description\": \"Full access to all SCEPman CertMaster functions like requesting and managing certificates\",
    \"displayName\": \"Full Admin\",
    \"isEnabled\": \"true\",
    \"value\": \"Admin.Full\"
}]'.Replace("`r", [String]::Empty).Replace("`n", [String]::Empty)

# Register CertMaster App
$appreglinescm = ExecuteAzCommandRobustly -azCommand "az ad app create --display-name SCEPman-CertMaster-xyz4 --reply-urls `"$CertMasterBaseURL/signin-oidc`" --app-roles '$CertmasterManifest'"
$appregjsoncm = [System.String]::Concat($appreglinescm)
$appregcm = ConvertFrom-Json $appregjsoncm
az ad sp create --id $appregcm.appId



# Add Microsoft Graph's User.Read as delegated permission for CertMaster
ExecuteAzCommandRobustly -azCommand "az ad app permission add --id $($appregcm.appId) --api $MSGraphAppId --api-permissions `"$MSGraphUserReadPermission=Scope`""
ExecuteAzCommandRobustly -azCommand "az ad app permission grant --id $($appregcm.appId) --api $MSGraphAppId --scope `"User.Read`""



### Add CertMaster app service authentication
# Use v2 auth commands
az extension add --name authV2

# Enable the authentication
az webapp auth microsoft update --name $CertMasterAppServiceName --resource-group $SCEPmanResourceGroup --client-id $appregcm.appId --issuer "https://sts.windows.net/$($tenant.tenantId)/v2.0" --yes

# Add the Redirect To
az webapp auth update --name $CertMasterAppServiceName --resource-group $SCEPmanResourceGroup --redirect-provider AzureActiveDirectory
