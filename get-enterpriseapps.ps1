$TenantId = Get-AzKeyVaultSecret -VaultName "Keysaz" -Name "TenantId" -AsPlainText
$ClientId = Get-AzKeyVaultSecret -VaultName "Keysaz" -Name "ClientId" -AsPlainText
$ClientSecret = Get-AzKeyVaultSecret -VaultName "Keysaz" -Name "clientSecret" -AsPlainText

$logonURI = "login.microsoftonline.com"
$graphURI = "graph.microsoft.com"

#Setup CSV Headers
"appName, userName, GroupName" | Out-File -FilePath output.csv -Encoding ASCII


# Create a hashtable for the body, the data needed for the token request
# The variables used are explained above

$Body = @{
    'tenant' = $TenantId
    'client_id' = $ClientId
    'scope' = "https://{0}/.default" -f $graphURI
    'client_secret' = $ClientSecret
    'grant_type' = 'client_credentials'
}

# Assemble a hashtable for splatting parameters, for readability
# The tenant id is used in the uri of the request as well as the body
$Params = @{
    'Uri' = "https://{0}/$TenantId/oauth2/v2.0/token" -f $logonURI
    'Method' = 'Post'
    'Body' = $Body
    'ContentType' = 'application/x-www-form-urlencoded'
}

$AuthResponse = Invoke-RestMethod @Params


$Headers = @{
    'Authorization' = "Bearer $($AuthResponse.access_token)"
}

# 1.	List all Registered Applications and Enterprise Applications

$allAppURI = "https://{0}/v1.0/servicePrincipals?$filter=eq(accountEnabled, 'true')&$orderby=displayName" -f $graphURI
$AppResult = Invoke-RestMethod -Uri $allAppURI -Headers $Headers

$Apps = $AppResult.value
while ($AppResult.'@odata.nextLink') {
    Write-Host "Getting another page of 100 apps..."
    $AppResult = Invoke-RestMethod -Uri $AppResult.'@odata.nextLink' -Headers $Headers
    $Apps += $AppResult.value
}

foreach ($app in $Apps)
{

  $appURI = "https://{0}/v1.0/servicePrincipals/{1}/appRoleAssignedTo" -f $graphURI,$app.id
  $EntityResult = Invoke-RestMethod -Uri $appURI -Headers $Headers
  if ($EntityResult.value){
    #Write-Host $app.displayName
    #Write-Host $EntityResult.value
    foreach($e in $EntityResult.value){
        #Write-Host $e.principalDisplayName "("$e.principalType")"
        Write-Host "Iterating Members..."
        
        if($e.principalType -eq "Group"){
           
            Write-Host "Enumerating Group Members..."
            #Write-Host $e.principalDisplayName
            $grpURI = "https://{0}/v1.0/groups/{1}/members" -f $graphURI,$e.principalId
            $grpResult = Invoke-RestMethod -Uri $grpURI -Headers $Headers
            $Members = $grpResult.value
            foreach ($member in $Members){
                
                #Write-Host $member.displayName
                "{0}, {1}, {2}" -f $app.displayName,$member.displayName,$e.principalDisplayName | Out-File -FilePath output.csv -Append -Encoding ASCII
            }
        }else{
            # Get User Role Assignments
            # https://graph.microsoft.com/v1.0/users/{id}/appRoleAssignments
            $usrAssignURI = "https://{0}/v1.0/users/{1}/appRoleAssigments"
            $usrAssignResult = Invoke-RestMethod -Uri $usrAssignURI -Headers $Headers
            $uAssignments = $usrAssignResult.value
            foreach ($uAssignment in $uAssignments){
                "{0}, {1}, -, {2}" -f $app.displayName,$e.principalDisplayName,$uAssignment | Out-File -FilePath output.csv -Append -Encoding ASCII
            }
            # Found a user added to app directly, no group
        }
    }
  }

}

