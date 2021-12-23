# for testing
#$env:SCEPMAN_APP_SERVICE_NAME = "as-scepman-deploytest"
#$env:CERTMASTER_APP_SERVICE_NAME = "aleen-as-certmaster-askjvljweklraesr"
#$env:SCEPMAN_RESOURCE_GROUP = "rg-SCEPman" # Optional

$SCEPmanAppServiceName = $env:SCEPMAN_APP_SERVICE_NAME
$CertMasterAppServiceName = $env:CERTMASTER_APP_SERVICE_NAME
$SCEPmanResourceGroup = $env:SCEPMAN_RESOURCE_GROUP

if ([String]::IsNullOrWhiteSpace($SCEPmanAppServiceName)) {
  $SCEPmanAppServiceName = Read-Host "Please enter the SCEPman app service name"
}

#az login

# Some hard-coded definitions
$MSGraphAppId = "00000003-0000-0000-c000-000000000000"
$MSGraphDirectoryReadAllPermission = "7ab1d382-f21e-4acd-a863-ba3e13f7da61"
$MSGraphDeviceManagementReadPermission = "2f51be20-0bb4-4fed-bf7b-db946066c75e"
$MSGraphUserReadPermission = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"

# "0000000a-0000-0000-c000-000000000000" # Service Principal App Id of Intune, not required here
$IntuneAppId = "c161e42e-d4df-4a3d-9b42-e7a3c31f59d4" # Well-known App ID of the Intune API
$IntuneSCEPChallengePermission = "39d724e8-6a34-4930-9a36-364082c35716"

$MAX_RETRY_COUNT = 4  # for some operations, retry a couple of times

$azureADAppNameForSCEPman = 'SCEPman-api' #Azure AD app name for SCEPman
$azureADAppNameForCertMaster = 'SCEPman-CertMaster' #Azure AD app name for certmaster

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

function ConvertLinesToObject($lines) {
    if($null -eq $lines) {
        return $null
    }
    $linesJson = [System.String]::Concat($lines)
    return ConvertFrom-Json $linesJson
}

function GetTenantDetails {
  return ConvertLinesToObject -lines $(az account show)
}

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
      $appRoleAssignments = ConvertLinesToObject -lines $(az rest --method get --url "https://graph.microsoft.com/v1.0/servicePrincipals/$principalId/appRoleAssignments")
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
    throw "Error $azErrorCode when executing $azCommand : $lastAzOutput"
  }
  else {
    return $lastAzOutput
  }
}

function GetResourceGroup {
  if ([String]::IsNullOrWhiteSpace($SCEPmanResourceGroup)) {
    # No resource group given, search for it now
    $scwebapp = ConvertLinesToObject -lines $(az webapp list --query "[?name=='$SCEPmanAppServiceName']")
    $SCEPmanResourceGroup = $scwebapp.resourceGroup
    if ([String]::IsNullOrWhiteSpace($SCEPmanResourceGroup)) {
      Write-Error "Unable to determine the resource group"
      throw "Unable to determine the resource group"
    }
  }
  return $SCEPmanResourceGroup;
}


function GetCertMasterAppServiceName {
    if ([String]::IsNullOrWhiteSpace($CertMasterAppServiceName)) {

    #       Criteria:
    #       - Only two App Services in SCEPman's resource group. One is SCEPman, the other the CertMaster candidate
    #       - Configuration value AppConfig:SCEPman:URL must be present, then it must be a CertMaster
    #       - In a default installation, the URL must contain SCEPman's app service name. We require this.

      $rgwebapps = ConvertLinesToObject -lines $(az webapp list --resource-group $SCEPmanResourceGroup)
      if($rgwebapps.Count -eq 2) {
        $potentialcmwebapp = $rgwebapps | ? {$_.name -ne $SCEPmanAppServiceName}
        $scepmanurlsettingcount = az webapp config appsettings list --name $potentialcmwebapp.name --resource-group $SCEPmanResourceGroup --query "[?name=='AppConfig:SCEPman:URL'].value | length(@)"
        if($scepmanurlsettingcount -eq 1) {
            $hascorrectscepmanurl = az webapp config appsettings list --name $potentialcmwebapp.name --resource-group $SCEPmanResourceGroup --query "contains([?name=='AppConfig:SCEPman:URL'].value | [0], '$SCEPmanAppServiceName')"
            if($hascorrectscepmanurl -eq $true) {
              $CertMasterAppServiceName = $potentialcmwebapp.name
            }
        }
      }
      if ([String]::IsNullOrWhiteSpace($CertMasterAppServiceName)) {
        Write-Warning "Unable to determine the Certmaster app service name"
        return $null
      }
    }
    return $CertMasterAppServiceName;
}

function CreateCertMasterAppService {
  $CertMasterAppServiceName = GetCertMasterAppServiceName

  if ($null -eq $CertMasterAppServiceName) {
    $scwebapp = ConvertLinesToObject -lines $(az webapp list --query "[?name=='$SCEPmanAppServiceName']")
    $scwebapp.appServicePlanId
    $CertMasterAppServiceName = $scwebapp.name
    if ($CertMasterAppServiceName.Length -gt 57) {
      $CertMasterAppServiceName = $CertMasterAppServiceName.Substring(0,57)
    }
    $CertMasterAppServiceName += "-cm"
    # TODO: Ask the user to confirm the name

    $dummy = az webapp create --resource-group $SCEPmanResourceGroup --plan $scwebapp.appServicePlanId --name $CertMasterAppServiceName --assign-identity [system]

    # Do all the configuration that the ARM template does normally
    $CertmasterAppSettings = @{
      WEBSITE_RUN_FROM_PACKAGE = "https://raw.githubusercontent.com/scepman/install/master/dist-certmaster/CertMaster-Artifacts-Intern.zip";
      "AppConfig:AuthConfig:TenantId" = $tenant.id;
      "AppConfig:SCEPman:URL" = "https://$($scwebapp.defaultHostName)/";
      "AppConfig:AzureStorage:TableStorageEndpoint" = [string]::Empty # TODO: Enter the right value
    } | ConvertTo-Json -Compress
    $CertMasterAppSettings = $CertmasterAppSettings.Replace('"', '\"')

    $dummy = az webapp config appsettings set --name $CertMasterAppServiceName --resource-group $SCEPmanResourceGroup --settings $CertmasterAppSettings
    # TODO: Enforce HTTPS
    # TODO: Switch to 64 Bits plattform
    # TODO: Compare other settings
  }

  return $CertMasterAppServiceName
}

function GetServicePrincipal($appServiceNameParam, $resourceGroupParam) {
    return ConvertLinesToObject -lines $(az webapp identity show --name $appServiceNameParam --resource-group $resourceGroupParam)
}

function GetAzureResourceAppId($appId) {
    return $(az ad sp list --filter "appId eq '$appId'" --query [0].objectId --out tsv)
}

function SetManagedIdentityPermissions($principalId, $resourcePermissions) {
    $graphEndpointForAppRoleAssignments = "https://graph.microsoft.com/v1.0/servicePrincipals/$($principalId)/appRoleAssignments"
    $alreadyAssignedPermissions = az rest --method get --uri $graphEndpointForAppRoleAssignments --headers "Content-Type=application/json" --query 'value[].appRoleId' --output tsv
    
    ForEach($resourcePermission in $resourcePermissions) {
        if(($alreadyAssignedPermissions -contains $resourcePermission.appRoleId) -eq $false) {
            $bodyToAddPermission = "{'principalId': '$($principalId)','resourceId': '$($resourcePermission.resourceId)','appRoleId':'$($resourcePermission.appRoleId)'}"
            $dummy = az rest --method post --uri $graphEndpointForAppRoleAssignments --body $bodyToAddPermission --headers "Content-Type=application/json"
        }
    }
}


function GetAzureADApp($name) {
    return ConvertLinesToObject -lines $(az ad app list --filter "displayname eq '$name'" --query "[0]")
}

function CreateServicePrincipal($appId) {
    $sp = ConvertLinesToObject -lines $(az ad sp list --filter "appId eq '$appId'" --query "[0]")
    if($null -eq $sp) {
        #App Registration SP doesn't exist.
        return ConvertLinesToObject -lines $(ExecuteAzCommandRobustly -azCommand "az ad sp create --id $appId")
    }
    else {
        return $sp
    }
}

function RegisterAzureADApp($name, $manifest, $replyUrls = $null) {
    $azureAdAppReg = ConvertLinesToObject -lines $(az ad app list --filter "displayname eq '$name'" --query "[0]")
    if($null -eq $azureAdAppReg) {
        #App Registration doesn't exist.
        if($null -eq $replyUrls) {
            $azureAdAppReg = ExecuteAzCommandRobustly -azCommand "az ad app create --display-name '$name' --app-roles '$manifest'"     
        }
        else {
            $azureAdAppReg = ExecuteAzCommandRobustly -azCommand "az ad app create --display-name '$name' --app-roles '$manifest' --reply-urls '$replyUrls'" 
        }
    }  
    return $azureAdAppReg
}

function AddDelegatedPermissionToCertMasterApp($appId) {
    $certMasterPermissions = ConvertLinesToObject -lines $(az ad app permission list --id $appId --query "[0]")
    if($null -eq ($certMasterPermissions.resourceAccess | ? { $_.id -eq $MSGraphUserReadPermission })) {
        $dummy = ExecuteAzCommandRobustly -azCommand "az ad app permission add --id $appId --api $MSGraphAppId --api-permissions `"$MSGraphUserReadPermission=Scope`" 2>&1"
    }
    $dummy = ExecuteAzCommandRobustly -azCommand "az ad app permission grant --id $appId --api $MSGraphAppId --scope `"User.Read`""
}

$tenant = GetTenantDetails
$SCEPmanResourceGroup = GetResourceGroup
$CertMasterAppServiceName = CreateCertMasterAppService
$CertMasterBaseURL = "https://$CertMasterAppServiceName.azurewebsites.net"
$graphResourceId = GetAzureResourceAppId -appId $MSGraphAppId
$intuneResourceId = GetAzureResourceAppId -appId $IntuneAppId

# Service principal of System-assigned identity of SCEPman
$serviceprincipalsc = GetServicePrincipal -appServiceNameParam $SCEPmanAppServiceName -resourceGroupParam $SCEPmanResourceGroup

# Service principal of System-assigned identity of CertMaster
$serviceprincipalcm = GetServicePrincipal -appServiceNameParam $CertMasterAppServiceName -resourceGroupParam $SCEPmanResourceGroup

### Set managed identity permissions for SCEPman
$resourcePermissionsForSCEPman = 
    @([pscustomobject]@{'resourceId'=$graphResourceId;'appRoleId'=$MSGraphDirectoryReadAllPermission;},
      [pscustomobject]@{'resourceId'=$graphResourceId;'appRoleId'=$MSGraphDeviceManagementReadPermission;},
      [pscustomobject]@{'resourceId'=$intuneResourceId;'appRoleId'=$IntuneSCEPChallengePermission;}
)
SetManagedIdentityPermissions -principalId $serviceprincipalsc.principalId -resourcePermissions $resourcePermissionsForSCEPman


### SCEPman App Registration

# Register SCEPman App
$appregsc = RegisterAzureADApp -name $azureADAppNameForSCEPman -manifest $ScepmanManifest
$spsc = CreateServicePrincipal -appId $appregsc.appId

$ScepManSubmitCSRPermission = $appregsc.appRoles[0].id

# Expose SCEPman API
ExecuteAzCommandRobustly -azCommand "az ad app update --id $($appregsc.appId) --identifier-uris `"api://$($appregsc.appId)`""

# Allow CertMaster to submit CSR requests to SCEPman API
$resourcePermissionsForCertMaster = @([pscustomobject]@{'resourceId'=$($spsc.objectId);'appRoleId'=$ScepManSubmitCSRPermission;})
SetManagedIdentityPermissions -principalId $serviceprincipalcm.principalId -resourcePermissions $resourcePermissionsForCertMaster


### CertMaster App Registration

# Register CertMaster App
$appregcm = RegisterAzureADApp -name $azureADAppNameForCertMaster -manifest $CertmasterManifest -replyUrls `"$CertMasterBaseURL/signin-oidc`"
$dummy = CreateServicePrincipal -appId $appregcm.appId

# Add Microsoft Graph's User.Read as delegated permission for CertMaster
AddDelegatedPermissionToCertMasterApp -appId $appregcm.appId



### Add CertMaster app service authentication
# Use v2 auth commands
# az extension add --name authV2

# Enable the authentication
# az webapp auth microsoft update --name $CertMasterAppServiceName --resource-group $SCEPmanResourceGroup --client-id $appregcm.appId --issuer "https://sts.windows.net/$($tenant.tenantId)/v2.0" --yes

# Add the Redirect To
# az webapp auth update --name $CertMasterAppServiceName --resource-group $SCEPmanResourceGroup --redirect-provider AzureActiveDirectory

# Add ApplicationId in SCEPman web app settings
$ScepManAppSettings = "{\`"AppConfig:AuthConfig:ApplicationId\`":\`"$($appregsc.appId)\`"}".Replace("`r", [String]::Empty).Replace("`n", [String]::Empty)
$dummy = az webapp config appsettings set --name $SCEPmanAppServiceName --resource-group $SCEPmanResourceGroup --settings $ScepManAppSettings

# Add ApplicationId and SCEPman API scope in certmaster web app settings
$CertmasterAppSettings = "{\`"AppConfig:AuthConfig:ApplicationId\`":\`"$($appregcm.appId)\`",\`"AppConfig:AuthConfig:SCEPmanAPIScope\`":\`"api://$($appregsc.appId)\`"}".Replace("`r", [String]::Empty).Replace("`n", [String]::Empty)
$dummy = az webapp config appsettings set --name $CertMasterAppServiceName --resource-group $SCEPmanResourceGroup --settings $CertmasterAppSettings
