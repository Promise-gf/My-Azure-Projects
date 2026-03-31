# ─────────────────────────────────────────────────────────────────────────────
# Azure Entra ID + RBAC + Conditional Access Script
# Designed to run non-interactively in GitHub Actions via OIDC
# ─────────────────────────────────────────────────────────────────────────────

# 1. Clean Session
Clear-AzContext -Force -ErrorAction SilentlyContinue
Disconnect-MgGraph -ErrorAction SilentlyContinue

# 2. Define Variables
$TenantId       = $env:AZURE_TENANT_ID
$SubscriptionId = $env:AZURE_SUBSCRIPTION_ID
$PlainPassword  = $env:USER_PASSWORD
$ClientId       = $env:AZURE_CLIENT_ID

if (-not $TenantId -or -not $SubscriptionId -or -not $PlainPassword -or -not $ClientId) {
    Write-Error "Missing required environment variables: AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID, USER_PASSWORD, AZURE_CLIENT_ID"
    exit 1
}

$passwordProfile = @{
    Password                      = $PlainPassword
    ForceChangePasswordNextSignIn = $true
}

$usersToCreate = @(
    @{ DisplayName = "John Doe";    UserPrincipalName = "johndoe@swifttfinancesoutlook.onmicrosoft.com";    Alias = "johndoe"    },
    @{ DisplayName = "Jane Smith";  UserPrincipalName = "janesmith@swifttfinancesoutlook.onmicrosoft.com";  Alias = "janesmith"  },
    @{ DisplayName = "Bob Johnson"; UserPrincipalName = "bobjohnson@swifttfinancesoutlook.onmicrosoft.com"; Alias = "bobjohnson" }
)

$groupName = "CloudOps-Team"

# ─────────────────────────────────────────────────────────────────────────────
# 3. Fetch the OIDC assertion once — reused for both Az and Graph token requests
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "Fetching OIDC assertion from GitHub Actions..." -ForegroundColor Cyan

$oidcToken = (Invoke-RestMethod `
    -Uri     "$($env:ACTIONS_ID_TOKEN_REQUEST_URL)&audience=api://AzureADTokenExchange" `
    -Headers @{ Authorization = "Bearer $($env:ACTIONS_ID_TOKEN_REQUEST_TOKEN)" }
).value

if (-not $oidcToken) {
    Write-Error "Failed to retrieve OIDC token from GitHub Actions. Ensure id-token: write permission is set."
    exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
# 4. Connect to Azure (Az PowerShell)
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "Connecting to Azure via OIDC..." -ForegroundColor Cyan

Connect-AzAccount `
    -ServicePrincipal `
    -TenantId       $TenantId `
    -ApplicationId  $ClientId `
    -FederatedToken $oidcToken `
    -ErrorAction Stop | Out-Null

Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
Write-Host "  ✅ Azure connected (Subscription: $SubscriptionId)" -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────────────────
# 5. Connect to Microsoft Graph
#
#    Root cause of InvalidAuthenticationToken:
#    Get-AzAccessToken returns a token scoped for ARM, not Graph. Even when
#    -ResourceTypeName MSGraph is specified, the resulting token is sometimes
#    wrapped or formatted in a way that newer Microsoft.Graph SDK versions
#    (v2+) reject with IDX14102 (invalid Base64Url header).
#
#    Fix: request a Graph-scoped token directly from the Entra ID token
#    endpoint using a client_credentials grant with the OIDC assertion as the
#    client_assertion (federated identity credential flow). This produces a
#    clean bearer token the Graph SDK always accepts.
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan

$graphTokenResponse = Invoke-RestMethod `
    -Method POST `
    -Uri    "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
    -ContentType "application/x-www-form-urlencoded" `
    -Body   @{
        grant_type            = "urn:ietf:params:oauth:grant-type:jwt-bearer"
        client_id             = $ClientId
        client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
        client_assertion      = $oidcToken
        scope                 = "https://graph.microsoft.com/.default"
        requested_token_use   = "on_behalf_of"
    } `
    -ErrorAction SilentlyContinue

# OBO requires delegated flow — if the app is service principal only, use
# client_credentials with the federated assertion instead
if (-not $graphTokenResponse -or -not $graphTokenResponse.access_token) {
    Write-Host "  OBO flow unavailable, trying client_credentials federated flow..." -ForegroundColor Gray
    $graphTokenResponse = Invoke-RestMethod `
        -Method POST `
        -Uri    "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
        -ContentType "application/x-www-form-urlencoded" `
        -Body   @{
            grant_type            = "client_credentials"
            client_id             = $ClientId
            client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
            client_assertion      = $oidcToken
            scope                 = "https://graph.microsoft.com/.default"
        } `
        -ErrorAction Stop
}

if (-not $graphTokenResponse -or -not $graphTokenResponse.access_token) {
    Write-Error "Failed to acquire Microsoft Graph access token."
    exit 1
}

# Connect-MgGraph with a raw System.Security.SecureString token (SDK v2 compatible)
$secureGraphToken = ConvertTo-SecureString $graphTokenResponse.access_token -AsPlainText -Force
Connect-MgGraph -AccessToken $secureGraphToken -NoWelcome -ErrorAction Stop
Write-Host "  ✅ Microsoft Graph connected" -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────────────────
# 6. DRY RUN — stop here after verifying auth
# ─────────────────────────────────────────────────────────────────────────────
if ($env:DRY_RUN -eq "true") {
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "DRY_RUN MODE: Auth verified. Skipping resource creation." -ForegroundColor Yellow
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    exit 0
}

# ─────────────────────────────────────────────────────────────────────────────
# 7. Create Users
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "Processing Users..." -ForegroundColor Cyan
$createdUsers = @()

foreach ($userDef in $usersToCreate) {
    $existingUser = Get-MgUser -Filter "UserPrincipalName eq '$($userDef.UserPrincipalName)'" -ErrorAction SilentlyContinue

    if ($existingUser) {
        Write-Host "  [SKIP] User $($userDef.UserPrincipalName) already exists." -ForegroundColor Yellow
        $createdUsers += $existingUser
    }
    else {
        try {
            $newUser = New-MgUser `
                -DisplayName         $userDef.DisplayName `
                -UserPrincipalName   $userDef.UserPrincipalName `
                -AccountEnabled:$true `
                -PasswordProfile     $passwordProfile `
                -MailNickname        $userDef.Alias `
                -UsageLocation       "US" `
                -ErrorAction Stop

            Write-Host "  [OK] Created user $($userDef.UserPrincipalName)" -ForegroundColor Green
            $createdUsers += $newUser
        }
        catch {
            Write-Error "  [ERR] Failed to create user: $($_.Exception.Message)"
        }
    }
}

Write-Host "Waiting 20 seconds for Entra ID replication..." -ForegroundColor Gray
Start-Sleep -Seconds 20


# ─────────────────────────────────────────────────────────────────────────────
# 8. Create Group
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "Processing Group..." -ForegroundColor Cyan
$group = Get-MgGroup -Filter "displayName eq '$groupName'" -ErrorAction SilentlyContinue

if (-not $group) {
    try {
        $group = New-MgGroup `
            -DisplayName     $groupName `
            -MailNickname    "CloudOps" `
            -MailEnabled:$false `
            -SecurityEnabled:$true `
            -ErrorAction Stop
        Write-Host "  [OK] Created group $groupName" -ForegroundColor Green
    }
    catch {
        Write-Error "  [ERR] Failed to create group: $($_.Exception.Message)"
    }
}
else {
    Write-Host "  [SKIP] Group $groupName already exists." -ForegroundColor Yellow
}


# ─────────────────────────────────────────────────────────────────────────────
# 9. Add Members to Group
# ─────────────────────────────────────────────────────────────────────────────
if ($group -and $group.Id) {
    Write-Host "Processing Group Membership..." -ForegroundColor Cyan
    foreach ($user in $createdUsers) {
        if (-not $user.Id) { continue }

        $isMember = Get-MgGroupMember -GroupId $group.Id -Filter "Id eq '$($user.Id)'" -ErrorAction SilentlyContinue
        if (-not $isMember) {
            try {
                New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $user.Id -ErrorAction Stop
                Write-Host "  [OK] Added $($user.UserPrincipalName)" -ForegroundColor Green
            }
            catch {
                Write-Warning "  [WARN] Could not add $($user.UserPrincipalName): $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "  [SKIP] $($user.UserPrincipalName) already in group." -ForegroundColor Yellow
        }
    }
}
else {
    Write-Error "Group ID not found. Cannot add members."
}


# ─────────────────────────────────────────────────────────────────────────────
# 10. Azure Role Assignments (RBAC)
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "Processing Azure Roles..." -ForegroundColor Cyan
$scope = "/subscriptions/$SubscriptionId"
$roleMappings = @(
    @{ UPN = "johndoe@swifttfinancesoutlook.onmicrosoft.com";    Role = "Virtual Machine Contributor" },
    @{ UPN = "janesmith@swifttfinancesoutlook.onmicrosoft.com";  Role = "Reader"                      },
    @{ UPN = "bobjohnson@swifttfinancesoutlook.onmicrosoft.com"; Role = "Contributor"                 }
)

foreach ($mapping in $roleMappings) {
    $targetUser = $createdUsers | Where-Object { $_.UserPrincipalName -eq $mapping.UPN }
    if ($targetUser) {
        try {
            $roleDef = Get-AzRoleDefinition -Name $mapping.Role -ErrorAction Stop

            $exists = Get-AzRoleAssignment `
                -ObjectId           $targetUser.Id `
                -RoleDefinitionId   $roleDef.Id `
                -Scope              $scope `
                -ErrorAction SilentlyContinue

            if (-not $exists) {
                New-AzRoleAssignment `
                    -ObjectId         $targetUser.Id `
                    -RoleDefinitionId $roleDef.Id `
                    -Scope            $scope `
                    -ErrorAction Stop | Out-Null
                Write-Host "  [OK] Assigned '$($mapping.Role)' to $($mapping.UPN)" -ForegroundColor Green
            }
            else {
                Write-Host "  [SKIP] '$($mapping.Role)' already assigned." -ForegroundColor Yellow
            }
        }
        catch {
            if ($_.Exception.Message -match "Forbidden") {
                Write-Warning "  [ERR] Insufficient permissions. Grant 'User Access Administrator' or 'Owner' to the GitHub OIDC App in Subscription IAM."
                break
            }
            else {
                Write-Error "  [ERR] Role assignment failed: $($_.Exception.Message)"
            }
        }
    }
}


# ─────────────────────────────────────────────────────────────────────────────
# 11. Conditional Access Policy (MFA)
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "Processing Conditional Access Policy..." -ForegroundColor Cyan

if ($group -and $group.Id) {
    $policyName = "Require MFA for CloudOps-Team"

    $existingPolicy = Get-MgIdentityConditionalAccessPolicy `
        -Filter "displayName eq '$policyName'" `
        -ErrorAction SilentlyContinue

    if ($existingPolicy) {
        Write-Host "  [SKIP] Policy '$policyName' already exists." -ForegroundColor Yellow
    }
    else {
        $params = @{
            displayName   = $policyName
            state         = "enabled"
            conditions    = @{
                users          = @{ includeGroups = @($group.Id) }
                applications   = @{ includeApplications = @("All") }
                clientAppTypes = @("all")
            }
            grantControls = @{
                operator        = "OR"
                builtInControls = @("mfa")
            }
        }

        try {
            New-MgIdentityConditionalAccessPolicy -BodyParameter $params -ErrorAction Stop
            Write-Host "  [OK] Created Conditional Access Policy." -ForegroundColor Green
        }
        catch {
            Write-Error "  [ERR] Failed to create CA Policy: $($_.Exception.Message)"
            Write-Warning "  NOTE: Ensure the GitHub OIDC App has 'Policy.ReadWrite.ConditionalAccess' (Application permission) granted Admin Consent in Entra ID."
        }
    }
}
else {
    Write-Warning "  [SKIP] CA Policy skipped because Group ID is missing."
}

Write-Host "--------------------------------------------------------"
Write-Host "Script Complete." -ForegroundColor Cyan