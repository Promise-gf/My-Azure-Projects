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

# Build the Password Profile Hashtable
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
# 3. Connect to Azure via OIDC (works in both DRY_RUN and real execution)
#    pwsh runs in a fresh session — it does NOT inherit the Az context that
#    azure/login@v2 set in the bash shell, so we must Connect-AzAccount here.
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "Connecting to Azure via OIDC..." -ForegroundColor Cyan

# Request an OIDC token from the GitHub Actions token endpoint
$oidcToken = (Invoke-RestMethod `
    -Uri     "$($env:ACTIONS_ID_TOKEN_REQUEST_URL)&audience=api://AzureADTokenExchange" `
    -Headers @{ Authorization = "Bearer $($env:ACTIONS_ID_TOKEN_REQUEST_TOKEN)" } `
).value

if (-not $oidcToken) {
    Write-Error "Failed to retrieve OIDC token from GitHub Actions. Ensure id-token: write permission is set."
    exit 1
}

Connect-AzAccount `
    -ServicePrincipal `
    -TenantId       $TenantId `
    -ApplicationId  $ClientId `
    -FederatedToken $oidcToken `
    -ErrorAction Stop | Out-Null

Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
Write-Host "  ✅ Azure connected (Subscription: $SubscriptionId)" -ForegroundColor Green

Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
$graphToken = (Get-AzAccessToken -ResourceTypeName MSGraph -TenantId $TenantId -ErrorAction Stop).Token
Connect-MgGraph -AccessToken ($graphToken | ConvertTo-SecureString -AsPlainText -Force) -NoWelcome
Write-Host "  ✅ Microsoft Graph connected" -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────────────────
# 4. DRY RUN — stop here after verifying auth
# ─────────────────────────────────────────────────────────────────────────────
if ($env:DRY_RUN -eq "true") {
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "DRY_RUN MODE: Auth verified. Skipping resource creation." -ForegroundColor Yellow
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    exit 0
}

# ─────────────────────────────────────────────────────────────────────────────
# 5. Create Users
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
# 6. Create Group
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
# 7. Add Members to Group
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
# 8. Azure Role Assignments (RBAC)
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
# 9. Conditional Access Policy (MFA)
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