# 🔐 Azure Entra ID · RBAC · Conditional Access Automation

> Automates Azure user provisioning, group management, role-based access control (RBAC), and MFA enforcement via Conditional Access — running fully non-interactively in **GitHub Actions** using **OIDC (Workload Identity Federation)**.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Required Permissions](#required-permissions)
- [Environment Variables](#environment-variables)
- [What the Script Does](#what-the-script-does)
- [GitHub Actions Setup](#github-actions-setup)
- [Dry Run Mode](#dry-run-mode)
- [Security Considerations](#security-considerations)
- [Troubleshooting](#troubleshooting)

---

## Overview

This PowerShell script provisions and configures identity and access management resources in Azure Entra ID (formerly Azure Active Directory). It is designed to run **without any interactive login**, using the **OIDC federated identity credential** flow so no client secrets or certificates need to be stored as GitHub secrets.

**What it automates:**

| Task | Tool Used |
|---|---|
| Create Entra ID users | Microsoft Graph (PowerShell SDK) |
| Create a security group | Microsoft Graph (PowerShell SDK) |
| Add users to the group | Microsoft Graph (PowerShell SDK) |
| Assign Azure RBAC roles | Az PowerShell |
| Create a Conditional Access (MFA) policy | Microsoft Graph (PowerShell SDK) |

---

## Architecture

```
GitHub Actions Runner
        │
        │  OIDC Token (JWT)
        ▼
Entra ID Token Endpoint
        │
        ├──► ARM Token  ──► Az PowerShell (RBAC assignments)
        │
        └──► Graph Token ──► Microsoft Graph SDK
                                  ├── Users
                                  ├── Groups
                                  └── Conditional Access Policies
```

**Authentication flow:** The script fetches a single OIDC assertion from GitHub Actions, then exchanges it for two separate tokens — one scoped to Azure Resource Manager (for RBAC) and one scoped to Microsoft Graph (for Entra ID operations). This avoids the `InvalidAuthenticationToken` error that occurs when reusing an ARM token for Graph API calls.

---

## Prerequisites

### Tools & Modules

The following must be available on the GitHub Actions runner (or your local machine for testing):

- PowerShell 7+
- `Az` PowerShell module (`Install-Module Az`)
- `Microsoft.Graph` PowerShell SDK v2+ (`Install-Module Microsoft.Graph`)

### Azure Resources

- An Azure subscription
- An Entra ID tenant
- A **registered App (Service Principal)** in Entra ID configured with a **Federated Identity Credential** pointing to your GitHub repository

---

## Required Permissions

### Microsoft Graph — Application Permissions
> Grant these in **Entra ID → App Registrations → Your App → API Permissions**, then click **Grant Admin Consent**.

| Permission | Why It's Needed |
|---|---|
| `User.ReadWrite.All` | Create and read users |
| `Group.ReadWrite.All` | Create groups and manage membership |
| `Policy.ReadWrite.ConditionalAccess` | Create Conditional Access policies |
| `Directory.Read.All` | Read directory objects |

### Azure Subscription — RBAC
> Assign these to your App (Service Principal) in **Subscription → Access Control (IAM)**.

| Role | Why It's Needed |
|---|---|
| `User Access Administrator` | Assign RBAC roles to users |
| `Reader` (minimum) | Read subscription resources |

> ⚠️ **Least-Privilege Note:** `User Access Administrator` is broad. Consider scoping it to a specific resource group rather than the full subscription if your RBAC assignments only target resources in one group.

---

## Environment Variables

Set these as **GitHub Actions secrets** (or environment variables for local runs):

| Variable | Description | Required |
|---|---|---|
| `AZURE_TENANT_ID` | Your Entra ID Tenant ID | ✅ |
| `AZURE_SUBSCRIPTION_ID` | Target Azure Subscription ID | ✅ |
| `AZURE_CLIENT_ID` | App Registration (Service Principal) Client ID | ✅ |
| `USER_PASSWORD` | Initial password assigned to all created users | ✅ |
| `DRY_RUN` | Set to `"true"` to verify auth without creating resources | ❌ Optional |

---

## What the Script Does

The script runs through the following steps in order:

### Step 1 — Clean Session
Clears any existing Az or Graph sessions to ensure a clean, non-conflicting run.

### Step 2 — Fetch OIDC Token
Requests a short-lived OIDC JWT from GitHub Actions' built-in token endpoint. This token acts as the proof of identity for all subsequent authentication.

### Step 3 — Connect to Azure (Az PowerShell)
Uses the OIDC token as a **Federated Token** to authenticate as the Service Principal — no password or certificate needed.

### Step 4 — Connect to Microsoft Graph
Exchanges the OIDC assertion for a **Graph-scoped access token** via the client credentials federated flow. This is done directly against the Entra ID token endpoint to avoid the token format issues that occur when converting an ARM token for Graph use.

### Step 5 — Create Users
Creates three Entra ID users (skips if they already exist):

| Display Name | UPN | Usage Location |
|---|---|---|
| John Doe | johndoe@swifttfinancesoutlook.onmicrosoft.com | US |
| Jane Smith | janesmith@swifttfinancesoutlook.onmicrosoft.com | US |
| Bob Johnson | bobjohnson@swifttfinancesoutlook.onmicrosoft.com | US |

All users are created with `ForceChangePasswordNextSignIn: true`.

### Step 6 — Create Security Group
Creates a security group named **`CloudOps-Team`** (skips if it already exists). This group is used for both membership management and Conditional Access targeting.

### Step 7 — Add Members to Group
Adds all three users to the `CloudOps-Team` group. Already-existing memberships are skipped gracefully.

### Step 8 — Assign Azure RBAC Roles
Assigns subscription-scoped RBAC roles to each user:

| User | Role |
|---|---|
| John Doe | Virtual Machine Contributor |
| Jane Smith | Reader |
| Bob Johnson | Contributor |

### Step 9 — Create Conditional Access Policy
Creates a policy named **"Require MFA for CloudOps-Team"** that:
- Targets all members of the `CloudOps-Team` group
- Applies to **all cloud applications**
- Enforces **Multi-Factor Authentication (MFA)**
- Policy state: `Enabled`

---

## GitHub Actions Setup

### 1. Configure Federated Identity Credential

In **Entra ID → App Registrations → Your App → Certificates & Secrets → Federated credentials**, add:

```
Scenario:      GitHub Actions
Organisation:  <your-github-username-or-org>
Repository:    <your-repo-name>
Entity:        Branch
Branch:        main
```

### 2. Example Workflow

```yaml
name: Entra ID Provisioning

on:
  workflow_dispatch:
  push:
    branches: [main]
    paths:
      - 'scripts/entra-rbac.ps1'

permissions:
  id-token: write   # Required for OIDC token request
  contents: read

jobs:
  provision:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install PowerShell Modules
        shell: pwsh
        run: |
          Install-Module Az -Force -Scope CurrentUser -AllowClobber
          Install-Module Microsoft.Graph -Force -Scope CurrentUser

      - name: Run Provisioning Script
        shell: pwsh
        env:
          AZURE_TENANT_ID:       ${{ secrets.AZURE_TENANT_ID }}
          AZURE_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
          AZURE_CLIENT_ID:       ${{ secrets.AZURE_CLIENT_ID }}
          USER_PASSWORD:         ${{ secrets.USER_PASSWORD }}
          DRY_RUN:               "false"
        run: ./scripts/entra-rbac.ps1
```

---

## Dry Run Mode

Set `DRY_RUN=true` to validate authentication without creating any resources. The script will:

1. Fetch the OIDC token ✅
2. Connect to Azure ✅
3. Connect to Microsoft Graph ✅
4. **Stop before creating users, groups, roles, or policies** ✅

This is useful for verifying permissions and connectivity on a new environment before a full run.

```yaml
env:
  DRY_RUN: "true"
```

---

## Security Considerations

| Topic | Recommendation |
|---|---|
| **No stored secrets** | OIDC eliminates the need to store client secrets in GitHub |
| **Password handling** | `USER_PASSWORD` is read from an environment variable, never hardcoded. Rotate after first login. |
| **Force password change** | All users are created with `ForceChangePasswordNextSignIn: true` |
| **RBAC scope** | Roles are assigned at subscription scope. Narrow to resource group scope if possible. |
| **Conditional Access** | Policy is set to `enabled` immediately. Test in `reportOnly` mode first in production environments. |
| **Graph permissions** | Only grant the minimum Graph permissions listed above. Avoid `Directory.ReadWrite.All` unless necessary. |

---

## Troubleshooting

### `InvalidAuthenticationToken` when connecting to Graph
**Cause:** Reusing an ARM-scoped token for Microsoft Graph API calls.  
**Fix:** The script handles this automatically by requesting a Graph-scoped token directly from the token endpoint, bypassing `Get-AzAccessToken`.

---

### `Forbidden` error on RBAC assignment
**Cause:** The Service Principal does not have `User Access Administrator` or `Owner` on the subscription.  
**Fix:** Go to **Subscription → Access Control (IAM) → Add Role Assignment** and assign one of those roles to your App.

---

### `Policy.ReadWrite.ConditionalAccess` error
**Cause:** Admin consent has not been granted for the Conditional Access permission.  
**Fix:** Go to **Entra ID → App Registrations → API Permissions** and click **Grant Admin Consent**.

---

### Users not found immediately after creation
**Cause:** Entra ID replication lag.  
**Fix:** The script includes a `Start-Sleep -Seconds 20` delay after user creation to allow replication before attempting group membership operations.

---

*Built with Az PowerShell · Microsoft Graph PowerShell SDK · GitHub Actions OIDC*