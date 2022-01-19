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

#TODO az login only if not already logged in

$dummy = az login

# TODO: Now we are in the default seubscription. It may be the wrong subscription ...

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

function GetSubscriptionDetails {
  $subscriptions = ConvertLinesToObject -lines $(az account list)
  if ($subscriptions.count -gt 1){
    Write-Host "Multiple subscriptions found. Please select a subscription!"
    for($i = 0; $i -lt $subscriptions.count; $i++){
        Write-Host "$($i + 1): $($subscriptions[$i].name) | Subscription Id: $($subscriptions[$i].id) | Press '$($i + 1)' to use this subscription"
    }
    $selection = Read-Host -Prompt "Please enter the number of the subscription"
    $potentialSubscription = $subscriptions[$($selection - 1)]
    if($null -eq $potentialSubscription) {
        Write-Error "We couldn't find the selected subscription. Please try to re-run the script"
        throw "We couldn't find the selected subscription. Please try to re-run the script"
    }
  } else {
    $potentialSubscription = $subscriptions[0]
  }
  $dummy = az account set --subscription $($potentialSubscription.id)
  return $potentialSubscription
}

# It is intended to use for az cli add permissions and az cli add permissions admin
# $azCommand - The command to execute. 
# 
function ExecuteAzCommandRobustly($azCommand, $principalId = $null, $appRoleId = $null) {
  $azErrorCode = 1234 # A number not null
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
    $allwebapps = ConvertLinesToObject -lines $(az webapp list --query "[].{name : name, resourceGroup : resourceGroup}")
    ForEach($webapp in $allwebapps) {
        if($webapp.name -eq $SCEPmanAppServiceName) {
            return $webapp.resourceGroup;
        }
    }
    Write-Error "Unable to determine the resource group"
    throw "Unable to determine the resource group"
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
      Write-Information "$($rgwebapps.Count) web apps found in the resource group $SCEPmanResourceGroup. We are finding if the CertMaster app is already created"
      if($rgwebapps.Count -gt 1) {
        ForEach($potentialcmwebapp in $rgwebapps) {
            if($potentialcmwebapp.name -ne $SCEPmanAppServiceName) {
                $scepmanurlsettingcount = az webapp config appsettings list --name $potentialcmwebapp.name --resource-group $SCEPmanResourceGroup --query "[?name=='AppConfig:SCEPman:URL'].value | length(@)"
                if($scepmanurlsettingcount -eq 1) {
                    $scepmanUrl = az webapp config appsettings list --name $potentialcmwebapp.name --resource-group $SCEPmanResourceGroup --query "[?name=='AppConfig:SCEPman:URL'].value"
                    $hascorrectscepmanurl = $scepmanUrl.ToUpperInvariant().Contains($SCEPmanAppServiceName.ToUpperInvariant())
                    if($hascorrectscepmanurl -eq $true) {
                        Write-Information "CertMaster web app $($potentialcmwebapp.name) found."
                        $CertMasterAppServiceName = $potentialcmwebapp.name
                        return $potentialcmwebapp.name
                    }
                }
            }
        }
      }
      Write-Warning "Unable to determine the Certmaster app service name"
      return $null
    }
    return $CertMasterAppServiceName;
}

function CreateCertMasterAppService {
  $CertMasterAppServiceName = GetCertMasterAppServiceName
  $CreateCertMasterAppService = $false

  if($null -eq $CertMasterAppServiceName) {
    $CreateCertMasterAppService =  $true
  } else {
    $CertMasterWebAppsCount = az webapp list --resource-group $SCEPmanResourceGroup --query "[?name=='$CertMasterAppServiceName'] | length(@)"
    if(0 -eq $CertMasterWebAppsCount) {
        $CreateCertMasterAppService =  $true
    }
  }
  
  $scwebapp = ConvertLinesToObject -lines $(az webapp list --query "[?name=='$SCEPmanAppServiceName']")
  
  if($null -eq $CertMasterAppServiceName) {
    $CertMasterAppServiceName = $scwebapp.name
    if ($CertMasterAppServiceName.Length -gt 57) {
      $CertMasterAppServiceName = $CertMasterAppServiceName.Substring(0,57)
    }
    
    $CertMasterAppServiceName += "-cm"
    $potentialCertMasterAppServiceName = Read-Host "CertMaster web app not found. Please hit enter now if you want to create the app with name $CertMasterAppServiceName or enter the name of your choice, and then hit enter"
    
    if($potentialCertMasterAppServiceName) {
        $CertMasterAppServiceName = $potentialCertMasterAppServiceName
    }
  }

  if ($true -eq $CreateCertMasterAppService) {
    
    Write-Information "User selected to create the app with the name $CertMasterAppServiceName"

    $dummy = az webapp create --resource-group $SCEPmanResourceGroup --plan $scwebapp.appServicePlanId --name $CertMasterAppServiceName --assign-identity [system] --% --runtime "DOTNET|5.0"
    Write-Information "CertMaster web app $CertMasterAppServiceName created"

    # Do all the configuration that the ARM template does normally
    $CertmasterAppSettings = @{
      WEBSITE_RUN_FROM_PACKAGE = "https://raw.githubusercontent.com/scepman/install/master/dist-certmaster/CertMaster-Artifacts.zip";
      "AppConfig:AuthConfig:TenantId" = $subscription.tenantId;
      "AppConfig:SCEPman:URL" = "https://$($scwebapp.defaultHostName)/";
    } | ConvertTo-Json -Compress
    $CertMasterAppSettings = $CertmasterAppSettings.Replace('"', '\"')

    Write-Debug 'Configuring CertMaster web app settings'
    $dummy = az webapp config set --name $CertMasterAppServiceName --resource-group $SCEPmanResourceGroup --use-32bit-worker-process $false --ftps-state 'Disabled' --always-on $true
    $dummy = az webapp update --name $CertMasterAppServiceName --resource-group $SCEPmanResourceGroup --https-only $true
    $dummy = az webapp config appsettings set --name $CertMasterAppServiceName --resource-group $SCEPmanResourceGroup --settings $CertMasterAppSettings 
  }

  return $CertMasterAppServiceName
}

function GetStorageAccount {
    $storageaccounts = ConvertLinesToObject -lines $(az storage account list --resource-group $SCEPmanResourceGroup)
    if($storageaccounts.Count -gt 0) {
        $potentialStorageAccountName = Read-Host "We have found one or more existing storage accounts in the resource group $SCEPmanResourceGroup. Please hit enter now if you still want to create a new storage account or enter the name of the storage account you would like to use, and then hit enter"
        if(!$potentialStorageAccountName) {
            Write-Information "User selected to create a new storage account"
            return $null
        } else {
            $potentialStorageAccount = $storageaccounts | ? { $_.name -eq $potentialStorageAccountName }
            if($null -eq $potentialStorageAccount) {
                Write-Error "We couldn't find a storage account with name $potentialStorageAccountName. Please try to re-run the script"
                throw "We couldn't find a storage account with name $potentialStorageAccountName. Please try to re-run the script"
            } else {
                return $potentialStorageAccount
            }
        }
    }
    else {
        Write-Warning "Unable to determine the storage account"
        return $null
    }
}


function CreateScStorageAccount {
    $ScStorageAccount = GetStorageAccount
    if($null -eq $ScStorageAccount) {
        Write-Information 'Storage account not found. We will create one now'
        $storageAccountName = $SCEPmanResourceGroup.ToLower() -replace '[^a-z0-9]',''
        if($storageAccountName.Length -gt 19) {
            $storageAccountName = $storageAccountName.Substring(0,19)
        }
        $storageAccountName = "stg$($storageAccountName)cm"
        $potentialStorageAccountName = Read-Host "Storage account not found. Please hit enter now if you want to create the storage account with name $storageAccountName or enter the name of your choice, and then hit enter"
        if($potentialStorageAccountName) {
            $storageAccountName = $potentialStorageAccountName
        }
        $ScStorageAccount = ConvertLinesToObject -lines $(az storage account create --name $storageAccountName --resource-group $SCEPmanResourceGroup --sku 'Standard_LRS' --kind 'StorageV2' --access-tier 'Hot' --allow-blob-public-access $true --allow-cross-tenant-replication $false --allow-shared-key-access $false --enable-nfs-v3 $false --min-tls-version 'TLS1_2' --publish-internet-endpoints $false --publish-microsoft-endpoints $false --routing-choice 'MicrosoftRouting' --https-only $true)
        if($null -eq $ScStorageAccount) {
            Write-Error 'Storage account not found and we are unable to create one. Please check logs for more details before re-running the script'
            throw 'Storage account not found and we are unable to create one. Please check logs for more details before re-running the script'
        }
        Write-Information "Storage account $storageAccountName created"
    }
    Write-Information "Setting permissions in storage account for SCEPman and CertMaster"
    $dummy = az role assignment create --role 'Storage Table Data Contributor' --assignee-object-id $serviceprincipalcm.principalId --assignee-principal-type 'ServicePrincipal' --scope `/subscriptions/$($subscription.id)/resourceGroups/$SCEPmanResourceGroup/providers/Microsoft.Storage/storageAccounts/$($ScStorageAccount.name)`
    $dummy = az role assignment create --role 'Storage Table Data Contributor' --assignee-object-id $serviceprincipalsc.principalId --assignee-principal-type 'ServicePrincipal' --scope `/subscriptions/$($subscription.id)/resourceGroups/$SCEPmanResourceGroup/providers/Microsoft.Storage/storageAccounts/$($ScStorageAccount.name)`
    return $ScStorageAccount
}

function SetTableStorageEndpointsInScAndCmAppSettings {
    
    $existingTableStorageEndpointSettingSc = az webapp config appsettings list --name $SCEPmanAppServiceName --resource-group $SCEPmanResourceGroup --query "[?name=='AppConfig:CertificateStorage:TableStorageEndpoint'].value | [0]"
    $existingTableStorageEndpointSettingCm = az webapp config appsettings list --name $CertMasterAppServiceName --resource-group $SCEPmanResourceGroup --query "[?name=='AppConfig:AzureStorage:TableStorageEndpoint'].value | [0]"
    $storageAccountTableEndpoint = $null

    if(![string]::IsNullOrEmpty($existingTableStorageEndpointSettingSc)) {
        if(![string]::IsNullOrEmpty($existingTableStorageEndpointSettingCm) -and $existingTableStorageEndpointSettingSc -ne $existingTableStorageEndpointSettingCm) {
            Write-Error "Inconsistency: SCEPman($SCEPmanAppServiceName) and CertMaster($CertMasterAppServiceName) have different storage accounts configured"
            throw "Inconsistency: SCEPman($SCEPmanAppServiceName) and CertMaster($CertMasterAppServiceName) have different storage accounts configured"
        }
        $storageAccountTableEndpoint = $existingTableStorageEndpointSettingSc
    }

    if([string]::IsNullOrEmpty($storageAccountTableEndpoint) -and ![string]::IsNullOrEmpty($existingTableStorageEndpointSettingCm)) {
        $storageAccountTableEndpoint = $existingTableStorageEndpointSettingCm
    }

    if([string]::IsNullOrEmpty($storageAccountTableEndpoint)) {
        Write-Information "Getting storage account"
        $ScStorageAccount = CreateScStorageAccount
        $storageAccountTableEndpoint = $($ScStorageAccount.primaryEndpoints.table)
    } else {
        Write-Debug 'Storage account table endpoint found in app settings'        
    }

    Write-Debug "Configuring table storage endpoints in SCEPman and CertMaster"
    $dummy = az webapp config appsettings set --name $CertMasterAppServiceName --resource-group $SCEPmanResourceGroup --settings AppConfig:AzureStorage:TableStorageEndpoint=$storageAccountTableEndpoint
    $dummy = az webapp config appsettings set --name $SCEPmanAppServiceName --resource-group $SCEPmanResourceGroup --settings AppConfig:CertificateStorage:TableStorageEndpoint=$storageAccountTableEndpoint
}

function GetServicePrincipal($appServiceNameParam, $resourceGroupParam) {
    return ConvertLinesToObject -lines $(az webapp identity show --name $appServiceNameParam --resource-group $resourceGroupParam)
}

function GetAzureResourceAppId($appId) {
    return $(az ad sp list --filter "appId eq '$appId'" --query [0].objectId --out tsv)
}

function SetManagedIdentityPermissions($principalId, $resourcePermissions) {
    $graphEndpointForAppRoleAssignments = "https://graph.microsoft.com/v1.0/servicePrincipals/$($principalId)/appRoleAssignments"
    ConvertLinesToObject -lines $("az rest --method get --uri '$graphEndpointForAppRoleAssignments' --headers 'Content-Type=application/json' --query 'value[].appRoleId' --output tsv")
    $alreadyAssignedPermissions = ExecuteAzCommandRobustly -azCommand "az rest --method get --uri '$graphEndpointForAppRoleAssignments' --headers 'Content-Type=application/json' --query 'value[].appRoleId' --output tsv"
    
    ForEach($resourcePermission in $resourcePermissions) {
        if(($alreadyAssignedPermissions -contains $resourcePermission.appRoleId) -eq $false) {
            $bodyToAddPermission = "{'principalId': '$($principalId)','resourceId': '$($resourcePermission.resourceId)','appRoleId':'$($resourcePermission.appRoleId)'}"
            $dummy = ExecuteAzCommandRobustly -azCommand "az rest --method post --uri '$graphEndpointForAppRoleAssignments' --body `"$bodyToAddPermission`" --headers 'Content-Type=application/json'" -principalId $principalId -appRoleId $resourcePermission.appRoleId
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
            $azureAdAppReg = ConvertLinesToObject -lines $(ExecuteAzCommandRobustly -azCommand "az ad app create --display-name '$name' --app-roles '$manifest'")
        }
        else {
            $azureAdAppReg = ConvertLinesToObject -lines $(ExecuteAzCommandRobustly -azCommand "az ad app create --display-name '$name' --app-roles '$manifest' --reply-urls '$replyUrls'")
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

Write-Information "Configuring SCEPman and CertMaster"

Write-Information "Getting subscription details"
$subscription = GetSubscriptionDetails

Write-Information "Setting resource group"
$SCEPmanResourceGroup = GetResourceGroup

Write-Information "Getting CertMaster web app"
$CertMasterAppServiceName = CreateCertMasterAppService

# Service principal of System-assigned identity of SCEPman
$serviceprincipalsc = GetServicePrincipal -appServiceNameParam $SCEPmanAppServiceName -resourceGroupParam $SCEPmanResourceGroup

# Service principal of System-assigned identity of CertMaster
$serviceprincipalcm = GetServicePrincipal -appServiceNameParam $CertMasterAppServiceName -resourceGroupParam $SCEPmanResourceGroup

SetTableStorageEndpointsInScAndCmAppSettings

$CertMasterBaseURL = "https://$CertMasterAppServiceName.azurewebsites.net"
Write-Information "CertMaster web app url is $CertMasterBaseURL"

$SCEPmanBaseURL = "https://$SCEPmanAppServiceName.azurewebsites.net"

$graphResourceId = GetAzureResourceAppId -appId $MSGraphAppId
$intuneResourceId = GetAzureResourceAppId -appId $IntuneAppId


### Set managed identity permissions for SCEPman
$resourcePermissionsForSCEPman = 
    @([pscustomobject]@{'resourceId'=$graphResourceId;'appRoleId'=$MSGraphDirectoryReadAllPermission;},
      [pscustomobject]@{'resourceId'=$graphResourceId;'appRoleId'=$MSGraphDeviceManagementReadPermission;},
      [pscustomobject]@{'resourceId'=$intuneResourceId;'appRoleId'=$IntuneSCEPChallengePermission;}
)
Write-Information "Setting up permissions for SCEPman"
SetManagedIdentityPermissions -principalId $serviceprincipalsc.principalId -resourcePermissions $resourcePermissionsForSCEPman


Write-Information "Creating Azure AD app registration for SCEPman"
### SCEPman App Registration
# Register SCEPman App
$appregsc = RegisterAzureADApp -name $azureADAppNameForSCEPman -manifest $ScepmanManifest
$spsc = CreateServicePrincipal -appId $($appregsc.appId)

$ScepManSubmitCSRPermission = $appregsc.appRoles[0].id

# Expose SCEPman API
ExecuteAzCommandRobustly -azCommand "az ad app update --id $($appregsc.appId) --identifier-uris `"api://$($appregsc.appId)`""

Write-Information "Allowing CertMaster to submit CSR requests to SCEPman API"
# Allow CertMaster to submit CSR requests to SCEPman API
$resourcePermissionsForCertMaster = @([pscustomobject]@{'resourceId'=$($spsc.objectId);'appRoleId'=$ScepManSubmitCSRPermission;})
SetManagedIdentityPermissions -principalId $serviceprincipalcm.principalId -resourcePermissions $resourcePermissionsForCertMaster


Write-Information "Creating Azure AD app registration for CertMaster"
### CertMaster App Registration

# Register CertMaster App
$appregcm = RegisterAzureADApp -name $azureADAppNameForCertMaster -manifest $CertmasterManifest -replyUrls `"$CertMasterBaseURL/signin-oidc`"
$dummy = CreateServicePrincipal -appId $($appregcm.appId)

# Add Microsoft Graph's User.Read as delegated permission for CertMaster
AddDelegatedPermissionToCertMasterApp -appId $appregcm.appId


Write-Information "Configuring SCEPman and CertMaster web app settings"

# Add ApplicationId in SCEPman web app settings
$ScepManAppSettings = "{\`"AppConfig:AuthConfig:ApplicationId\`":\`"$($appregsc.appId)\`",\`"AppConfig:CertMaster:URL\`":\`"$($CertMasterBaseURL)\`"}".Replace("`r", [String]::Empty).Replace("`n", [String]::Empty)
$dummy = az webapp config appsettings set --name $SCEPmanAppServiceName --resource-group $SCEPmanResourceGroup --settings $ScepManAppSettings

$existingApplicationKeySc = az webapp config appsettings list --name $SCEPmanAppServiceName --resource-group $SCEPmanResourceGroup --query "[?name=='AppConfig:AuthConfig:ApplicationKey'].value | [0]"
if(![string]::IsNullOrEmpty($existingApplicationKeySc)) {
    $dummy = az webapp config appsettings set --name $SCEPmanAppServiceName --resource-group $SCEPmanResourceGroup --settings BackUp:AppConfig:AuthConfig:ApplicationKey=$existingApplicationKeySc
    $dummy = az webapp config appsettings delete --name $SCEPmanAppServiceName --resource-group $SCEPmanResourceGroup --setting-names AppConfig:AuthConfig:ApplicationKey
}

# Add ApplicationId and SCEPman API scope in certmaster web app settings
$CertmasterAppSettings = "{\`"AppConfig:AuthConfig:ApplicationId\`":\`"$($appregcm.appId)\`",\`"AppConfig:AuthConfig:SCEPmanAPIScope\`":\`"api://$($appregsc.appId)\`"}".Replace("`r", [String]::Empty).Replace("`n", [String]::Empty)
$dummy = az webapp config appsettings set --name $CertMasterAppServiceName --resource-group $SCEPmanResourceGroup --settings $CertmasterAppSettings

Write-Information "SCEPman and CertMaster configuration completed"