# 1. Clean Session
Clear-AzContext -Force -ErrorAction SilentlyContinue
Disconnect-MgGraph -ErrorAction SilentlyContinue

# 2. Define Variables
Write-Host "Enter your Tenant ID:" -ForegroundColor Cyan
$TenantId       = Read-Host

Write-Host "Enter your Subscription ID:" -ForegroundColor Cyan
$SubscriptionId = Read-Host

# Ask for password in the terminal (input is hidden/masked)
Write-Host "Enter a password for the new users (must meet complexity requirements):" -ForegroundColor Cyan
$securePassword = Read-Host -AsSecureString

# Convert SecureString to Plain Text (Required for Microsoft Graph API)
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
$PlainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

# Build the Password Profile Hashtable for New-MgUser
$passwordProfile = @{
    Password = $PlainPassword
    ForceChangePasswordNextSignIn = $true
}

$usersToCreate = @(
    @{ DisplayName = "John Doe";    UserPrincipalName = "johndoe@swifttfinancesoutlook.onmicrosoft.com";    Alias = "johndoe"    },
    @{ DisplayName = "Jane Smith";  UserPrincipalName = "janesmith@swifttfinancesoutlook.onmicrosoft.com";  Alias = "janesmith"  },
    @{ DisplayName = "Bob Johnson"; UserPrincipalName = "bobjohnson@swifttfinancesoutlook.onmicrosoft.com"; Alias = "bobjohnson" }
)

$groupName = "CloudOps-Team"

# 3. Connect (Force Tenant)
Write-Host "Connecting to Graph..." -ForegroundColor Cyan
Connect-MgGraph -TenantId $TenantId -Scopes "User.ReadWrite.All","Group.ReadWrite.All","Directory.ReadWrite.All","Policy.ReadWrite.ConditionalAccess"

Write-Host "Connecting to Azure..." -ForegroundColor Cyan
Connect-AzAccount -TenantId $TenantId
Set-AzContext -SubscriptionId $SubscriptionId


# 4. Create Users (Strict Check)

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
                -DisplayName $userDef.DisplayName `
                -UserPrincipalName $userDef.UserPrincipalName `
                -AccountEnabled:$true `
                -PasswordProfile $passwordProfile `
                -MailNickname $userDef.Alias `
                -UsageLocation "US" `
                -ErrorAction Stop
            
            Write-Host "  [OK] Created user $($userDef.UserPrincipalName)" -ForegroundColor Green
            $createdUsers += $newUser
        }
        catch {
            Write-Error "  [ERR] Failed to create user: $($_.Exception.Message)"
        }
    }
}

Write-Host "Waiting 20 seconds for replication..." -ForegroundColor Gray
Start-Sleep -Seconds 20


# 5. Create Group

Write-Host "Processing Group..." -ForegroundColor Cyan
$group = Get-MgGroup -Filter "displayName eq '$groupName'" -ErrorAction SilentlyContinue

if (-not $group) {
    try {
        $group = New-MgGroup -DisplayName $groupName -MailNickname "CloudOps" -MailEnabled:$false -SecurityEnabled:$true -ErrorAction Stop
        Write-Host "  [OK] Created group $groupName" -ForegroundColor Green
    }
    catch {
        Write-Error "  [ERR] Failed to create group: $($_.Exception.Message)"
    }
}
else {
    Write-Host "  [SKIP] Group $groupName already exists." -ForegroundColor Yellow
}


# 6. Add Members

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


# 7. Azure Role Assignments (RBAC)

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
            
            $exists = Get-AzRoleAssignment -ObjectId $targetUser.Id -RoleDefinitionId $roleDef.Id -Scope $scope -ErrorAction SilentlyContinue
            
            if (-not $exists) {
                New-AzRoleAssignment -ObjectId $targetUser.Id -RoleDefinitionId $roleDef.Id -Scope $scope -ErrorAction Stop | Out-Null
                Write-Host "  [OK] Assigned '$($mapping.Role)' to $($mapping.UPN)" -ForegroundColor Green
            }
            else {
                Write-Host "  [SKIP] '$($mapping.Role)' already assigned." -ForegroundColor Yellow
            }
        }
        catch {
            if ($_.Exception.Message -match "Forbidden") {
                Write-Warning "  [ERR] You do not have permission to assign roles. Please grant 'Owner' rights to your account in the Subscription IAM blade."
                break
            }
            else {
                Write-Error "  [ERR] Role assignment failed: $($_.Exception.Message)"
            }
        }
    }
}


# 8. Conditional Access Policy (MFA)

Write-Host "Processing Conditional Access Policy..." -ForegroundColor Cyan

if ($group -and $group.Id) {
    $policyName = "Require MFA for CloudOps-Team"
    
    $existingPolicy = Get-MgIdentityConditionalAccessPolicy -Filter "displayName eq '$policyName'" -ErrorAction SilentlyContinue

    if ($existingPolicy) {
        Write-Host "  [SKIP] Policy '$policyName' already exists." -ForegroundColor Yellow
    }
    else {
        $params = @{
            displayName = $policyName
            state       = "enabled"
            conditions  = @{
                users = @{
                    includeGroups = @($group.Id)
                }
                applications = @{
                    includeApplications = @("All")
                }
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
            Write-Warning "  NOTE: Ensure your account has 'Policy.ReadWrite.ConditionalAccess' permission in Entra ID."
        }
    }
}
else {
    Write-Warning "  [SKIP] CA Policy skipped because Group ID is missing."
}

Write-Host "--------------------------------------------------------"
Write-Host "Script Complete." -ForegroundColor Cyan
Write-Host "NOTE: If you don't see Roles in the Portal, go to:" -ForegroundColor White
Write-Host "Subscriptions -> Azure subscription 1 -> Access control (IAM)" -ForegroundColor Gray