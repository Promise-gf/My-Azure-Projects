# Azure Secure Network Architecture — Hub & Spoke with Private Endpoints

![Azure](https://img.shields.io/badge/Azure-Infrastructure-0078D4?style=for-the-badge&logo=microsoftazure&logoColor=white)
![Terraform](https://img.shields.io/badge/IaC-Terraform-7B42BC?style=for-the-badge&logo=terraform&logoColor=white)
![Architecture](https://img.shields.io/badge/Architecture-Hub_and_Spoke-28A745?style=for-the-badge)
![Zero Trust](https://img.shields.io/badge/Security-Zero_Trust-DC3545?style=for-the-badge)

> A production-grade, modular Azure network infrastructure built entirely with Terraform — designed around a real-world financial services security problem.

---

## ⚠️ Critical Prerequisite — Remote State Storage Must Exist First

> **Before running `terraform init` or any deployment step, you must manually create the remote state backend storage account.** Terraform cannot create its own backend — the storage account must exist before Terraform is initialised. Skipping this step will cause `terraform init` to fail with a `ResourceGroupNotFound` error.

See the [Bootstrap section](#bootstrap-one-time-before-terraform-init) for the exact commands.

---

## The Problem

**CreditBridge** is a fictional Nigerian digital lending startup. Their engineering team built their initial Azure infrastructure rapidly during a funding sprint — trading security and governance for speed to market. Six months later, a routine third-party security audit exposed the following:

- Their **Storage Account** — holding customer BVN data, loan agreements, and KYC documents — was reachable from any IP on the public internet, secured only by a rotating access key stored in a `.env` file on a developer's laptop. The account had received **847 unauthorised access attempts in 30 days**.
- **SSH port 22 was open to `0.0.0.0/0`** on all application servers, protected only by weak password authentication.
- All traffic between application servers and the Storage Account was **travelling over the public internet** — exposing financial PII to interception.
- Resources had been provisioned manually for months, resulting in **chaotic, inconsistent naming** (`new-vnet`, `vnet-2-final`, `PROD-Network-USE`) that made automation and auditing impossible.
- The `terraform.tfstate` file — containing plaintext resource IDs, storage keys, and configuration data — was stored on a single developer's laptop with no backup and no state locking.
- An upcoming **CBN (Central Bank of Nigeria) compliance audit** and obligations under **NDPR** required that all customer PII never traverse the public internet and that all infrastructure be version-controlled and reproducible.

**The engineering challenge: redesign the network so that sensitive resources are invisible to the public internet, enforce strict traffic boundaries between application tiers, and allow authorised engineers to access resources securely — all defined as repeatable, auditable code.**

---

## The Solution

| Problem                                   | Solution                                                                           |
| ----------------------------------------- | ---------------------------------------------------------------------------------- |
| Storage reachable from public internet    | Private Endpoint — blob traffic never leaves the Microsoft backbone                |
| SSH ports exposed to the internet         | Azure Bastion (no open ports) + VPN Gateway provisioned for tunnel access          |
| Sensitive data traversing public internet | Private DNS Zone resolves storage to internal RFC 1918 IP automatically            |
| No traffic segmentation between tiers     | Dedicated subnets per tier with dynamically generated, tiered NSG rules            |
| Inconsistent resource naming              | Centralised `locals` block generates standardised names across all 60+ resources   |
| Monolithic infrastructure code            | 9 fully decoupled Terraform modules — each independently updateable                |
| No audit trail or monitoring              | Log Analytics Workspace with diagnostic settings on all critical resources         |
| Secrets in `.env` files                   | Azure Key Vault with RBAC authorisation and network-restricted access              |
| State file on developer laptop            | Remote state in Azure Blob Storage with encryption at rest and lease-based locking |

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                          AZURE SUBSCRIPTION                              │
│                                                                          │
│  ┌──────────────────────────────── HUB VNET (10.10.0.0/16) ──────────┐  │
│  │                                                                    │  │
│  │  ┌────────────┐   ┌────────────┐   ┌──────────────────────────┐  │  │
│  │  │  snet-web  │   │  snet-app  │   │      snet-database        │  │  │
│  │  │10.10.1.0/24│──▶│10.10.2.0/24│──▶│      10.10.3.0/24         │  │  │
│  │  │ HTTP/HTTPS │   │ Port 8080  │   │   SQL 1433 from App only  │  │  │
│  │  │ from inet  │   │ from Web   │   │                           │  │  │
│  │  └────────────┘   └────────────┘   └──────────────────────────┘  │  │
│  │                                                                    │  │
│  │  ┌────────────┐   ┌────────────┐   ┌──────────────────────────┐  │  │
│  │  │  snet-pe   │   │  Bastion   │   │     GatewaySubnet         │  │  │
│  │  │10.10.4.0/24│   │  Subnet    │   │   10.10.255.224/27        │  │  │
│  │  │PE: 10.10.  │   │10.10.254.0 │   │  VPN Gateway (VpnGw1)    │  │  │
│  │  │    4.4     │   │    /26     │   │  OpenVPN · Cert Auth      │  │  │
│  │  │(private)   │   │            │   │  [provisioned — pending   │  │  │
│  │  │            │   │            │   │   cert upload to activate]│  │  │
│  │  └────────────┘   └────────────┘   └──────────────────────────┘  │  │
│  │                                                                    │  │
│  │  ┌──────────────────────────────────────────────────────────────┐ │  │
│  │  │  AzureFirewallSubnet (10.10.253.0/26)                       │ │  │
│  │  │  Azure Firewall — inspects all outbound traffic             │ │  │
│  │  │  Diagnostic logs → Log Analytics Workspace                  │ │  │
│  │  └──────────────────────────────────────────────────────────────┘ │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                    VNet Peering (Gateway Transit enabled) ↕               │
│  ┌──────────────────────── SPOKE VNET (10.20.0.0/16) ────────────────┐  │
│  │   snet-workload (10.20.1.0/24)                                    │  │
│  │   Isolated workload network — routes through Hub VPN Gateway      │  │
│  │   (Gateway Transit: saves ~$140/month vs deploying a 2nd gateway) │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│  Storage Account        Private DNS Zone              Key Vault          │
│  Public access: DISABLED  privatelink.blob.core.      RBAC + network     │
│  Resolved internally      windows.net → 10.10.4.4     restricted        │
│  as 10.10.4.4                                                            │
│                                                                          │
│  Log Analytics Workspace    Remote State Backend (rg-tfstate)            │
│  All diagnostics stream     Azure Blob — encrypted, versioned,           │
│  here: Firewall, NSG,       lease-locked, isolated resource group        │
│  Bastion, VPN, Storage                                                   │
└──────────────────────────────────────────────────────────────────────────┘
                ↑
      VPN Tunnel (OpenVPN · Point-to-Site)
                ↑
  Remote Engineer (192.168.10.0/24 pool)
  Connects via VPN first — then accesses all resources privately
```

### Traffic Flow

| Path                     | Travels Over Public Internet? | Mechanism                      |
| ------------------------ | ----------------------------- | ------------------------------ |
| User → Web tier (80/443) | ✅ Intentional                | NSG inbound allow              |
| Web → App (8080)         | ❌ Private only               | NSG source CIDR restrict       |
| App → Database (1433)    | ❌ Private only               | NSG source CIDR restrict       |
| App → Blob Storage       | ❌ Private only               | Private Endpoint (10.10.4.4)   |
| Engineer → VMs           | ❌ Private only               | VPN tunnel → private subnet    |
| Spoke → Hub resources    | ❌ Private only               | VNet Peering + Gateway Transit |

---

## Project Structure

`main.tf` is a pure orchestrator — it wires modules together and passes resource IDs. Modules have no knowledge of the project's naming conventions or each other.

```
azure-secure-hub-spoke/
├── main.tf                   # Orchestrator: calls modules, passes outputs as inputs
├── variables.tf              # Declarations with validations
├── locals.tf                 # Naming engine: generates all resource names from prefix+env+location
├── terraform.tfvars          # Feature toggles: VPN / Bastion / Firewall on/off for cost control
├── outputs.tf                # Subnet IDs, NSG IDs, PE IPs etc.
├── backend.tf                # Remote state: Azure Blob Storage backend
│
└── modules/
    ├── nsg/                  # Dynamic NSG: accepts tier_type string, generates tiered rules
    ├── vnet/                 # VNet builder: subnets, NSG associations, safe conditional arrays
    ├── peering/              # Bidirectional Hub-Spoke peering with Gateway Transit
    ├── endpoints/            # Private Endpoint + DNS Zone + A-record — fully automated
    ├── vpn/                  # VPN Gateway: VpnGw1, OpenVPN, certificate authentication
    ├── bastion/              # Azure Bastion: browser-based VM access, no open ports
    ├── firewall/             # Azure Firewall: outbound inspection + diagnostic streaming
    ├── keyvault/             # Key Vault: RBAC-enabled, network-restricted secret store
    └── loganalytics/         # Central workspace for all diagnostic data
```

---

## Key Engineering Decisions

### 1. Dynamic NSG Rule Generation

Rather than four separate, hard-coded NSG modules, a single `modules/nsg/` accepts a `tier_type` string and generates the correct security rules at plan time using `dynamic "security_rule"` blocks iterating over a local rule map. Adding a new tier requires one new map entry — no new module.

```hcl
dynamic "security_rule" {
  for_each = local.tier_rules[var.tier_type]
  content {
    name                  = security_rule.value.name
    priority              = security_rule.value.priority
    source_address_prefix = security_rule.value.source_prefix
    destination_port_range = security_rule.value.port
    ...
  }
}
```

### 2. Centralised Naming Engine

Every resource name flows from a single `locals.tf` block. No module constructs its own name. Naming convention changes happen in exactly one file.

```hcl
locals {
  loc_abbr = { centralus = "cus", eastus = "eus", westeurope = "weu" }[var.location]

  name = {
    vnet_hub  = "${var.prefix}-${local.env_abbr}-vnet-hub-${local.loc_abbr}"
    nsg_web   = "${var.prefix}-${local.env_abbr}-nsg-web-${local.loc_abbr}"
    firewall  = "${var.prefix}-${local.env_abbr}-afw-${local.loc_abbr}"
    key_vault = "${var.prefix}-${local.env_abbr}-kv-${local.loc_abbr}"
  }
}
```

### 3. Feature Toggle Architecture

Every optional component is controlled by a boolean variable in a `count` block. The same configuration deploys as a minimal dev environment or a full production stack — without editing module code.

```hcl
# VPN Gateway only deploys if flag is true AND cert data is provided
resource "azurerm_virtual_network_gateway" "this" {
  count = var.deploy_vpn && var.vpn_root_cert_data != "" ? 1 : 0
  ...
}

# The P2S connection is a separate resource with its own toggle
resource "azurerm_virtual_network_gateway_connection" "p2s" {
  count = var.deploy_vpn_connection ? 1 : 0
  ...
}
```

> **Note on VPN status:** The VPN Gateway (VpnGw1 SKU) is fully provisioned and healthy. The Point-to-Site connection is not yet active — it requires a root certificate generated outside of Terraform (via PowerShell) to be uploaded as the final activation step. This is a deliberate two-stage approach: the gateway is validated before the certificate is bound, and the certificate is stored in Key Vault rather than passed through the Terraform pipeline.

### 4. Gateway Transit — Cost Optimisation

Instead of deploying a second VPN Gateway in the Spoke (~$140/month), the peering module configures `allow_gateway_transit = true` on the Hub and `use_remote_gateways = true` on the Spoke. Remote engineers connect once to the Hub Gateway and Azure routes them into the Spoke automatically.

### 5. Safe Conditional Output Pattern

Terraform conditional resources using `count` return a list. All optional module outputs use `try()` to return a safe empty string rather than an index-out-of-range error at plan time.

```hcl
output "firewall_id" {
  value = try(azurerm_firewall.this[0].id, "")
}
```

### 6. Enforced Deployment Dependencies

The Firewall module uses a compound `count` condition that prevents it from deploying without a Log Analytics Workspace — a compliance requirement under most security frameworks.

```hcl
count = var.deploy_firewall && var.deploy_log_analytics ? 1 : 0
```

---

## Remote State Management

By default, `terraform.tfstate` is written locally. In CreditBridge's original setup this file — containing resource IDs, access keys, and certificate data in plaintext — lived on one developer's laptop with no backup and no locking.

This project stores state in a dedicated Azure Storage Account in a separate resource group (`rg-tfstate`), completely isolated from the infrastructure it manages:

```
rg-tfstate/
└── tfstatexxxxxxxx  (Storage Account)
    └── tfstate      (Blob Container)
        └── network.terraform.tfstate
```

- **Encryption at rest** — Microsoft-managed keys on all blobs
- **Blob versioning** — every `apply` creates a new version; broken state can be rolled back instantly
- **Lease-based locking** — Terraform acquires a blob lease before every operation; concurrent runs are blocked automatically
- **Isolated resource group** — state survives even if the application resource group is deleted

---

## Bootstrap (One-Time, Before `terraform init`)

> **🚨 This step is mandatory. The remote state storage account must exist before `terraform init` is run — by any person, on any machine, or in any CI/CD pipeline. Terraform cannot create its own backend. If this step is skipped, `terraform init` will fail with:**
>
> ```
> Error: Failed to get existing workspaces
> ResourceGroupNotFound: Resource group 'rg-tfstate' could not be found.
> ```

Run these commands **once**, from any machine with Azure CLI access, before anything else:

```bash
# Step 1 — Create the dedicated state resource group
az group create \
  --name rg-tfstate \
  --location centralus

# Step 2 — Create the storage account (name must be globally unique)
STORAGE_ACCOUNT="tfstate$RANDOM"
az storage account create \
  --name $STORAGE_ACCOUNT \
  --resource-group rg-tfstate \
  --location centralus \
  --sku Standard_LRS \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false

# Step 3 — Create the blob container
az storage container create \
  --name tfstate \
  --account-name $STORAGE_ACCOUNT

# Step 4 — Enable blob versioning for state rollback
az storage account blob-service-properties update \
  --account-name $STORAGE_ACCOUNT \
  --resource-group rg-tfstate \
  --enable-versioning true

# Step 5 — Print the storage account name — save this value
echo "✅ Bootstrap complete. Storage account: $STORAGE_ACCOUNT"
```

> **Save the storage account name** printed in Step 5. You will need it in two places:
>
> - As the `storage_account_name` value in `backend.tf`
> - As the `BACKEND_STORAGE_ACCOUNT` secret in your GitHub Actions repository secrets

### Grant the Service Principal Access to the State Backend

If deploying via GitHub Actions with OIDC, the Service Principal also needs access to read and write the state file:

```bash
az role assignment create \
  --assignee <your-app-client-id> \
  --role "Storage Blob Data Contributor" \
  --scope /subscriptions/<subscription-id>/resourceGroups/rg-tfstate
```

---

## Deployment

> **Ensure the [Bootstrap](#bootstrap-one-time-before-terraform-init) step above has been completed before proceeding.**

```bash
# 1. Clone
git clone https://github.com/Promise-gf/My-Azure-Projects/tree/main/Terraform/Network%20Architecture
cd azure-secure-hub-spoke

# 2. Create the application resource group
az group create --name rg-corp-network-prod --location centralus

# 3. Initialise Terraform (connects to remote state backend — must exist first)
terraform init

# 4. Dry run
terraform plan -var-file="terraform.tfvars" -out=tfplan

# 5. Deploy
terraform apply tfplan
```

### Deployment Order Summary

```
Step 1 — Bootstrap (manual, one-time)
  └── Create rg-tfstate resource group
  └── Create tfstate storage account          ← MUST exist before step 2
  └── Create tfstate blob container

Step 2 — terraform init                       ← connects to backend created in Step 1
Step 3 — terraform plan
Step 4 — terraform apply
```

### Verify Zero-Trust Controls

```bash
# Confirm storage has no public endpoint
az storage account show \
  --name corpprodstxxxxxxxx \
  --resource-group rg-corp-network-prod \
  --query "{PublicAccess:properties.allowBlobPublicAccess,NetworkDefault:properties.networkAcls.defaultAction}"

# Confirm Private Endpoint resolves to internal IP
az network private-endpoint show \
  --name corp-prod-pe-storage-cus \
  --resource-group rg-corp-network-prod \
  --query "{FQDN:properties.customDnsConfigs[0].fqdn,PrivateIP:properties.customDnsConfigs[0].ipAddresses[0]}"

# Verify database NSG — SQL 1433 from App subnet only
az network nsg show \
  --name corp-prod-nsg-db-cus \
  --resource-group rg-corp-network-prod \
  --query "properties.securityRules[].{Name:name,Source:sourceAddressPrefix,Port:destinationPortRange,Access:access}" \
  --output table
```

---

## Resources Deployed

| Resource         | Name Pattern                        | Purpose                                              |
| ---------------- | ----------------------------------- | ---------------------------------------------------- |
| Hub VNet         | `corp-prod-vnet-hub-cus`            | Core network housing all shared infrastructure       |
| Spoke VNet       | `corp-prod-vnet-spoke-cus`          | Isolated workload boundary                           |
| NSG — Web        | `corp-prod-nsg-web-cus`             | HTTP/HTTPS inbound; denies all else                  |
| NSG — App        | `corp-prod-nsg-app-cus`             | Port 8080 from Web subnet only                       |
| NSG — Database   | `corp-prod-nsg-db-cus`              | SQL 1433 from App subnet only                        |
| NSG — Spoke      | `corp-prod-nsg-spoke-cus`           | Inbound from Hub VNet prefix only                    |
| Storage Account  | `corpprodstxxxxxxxx`                | Blob storage — public access fully disabled          |
| Private Endpoint | `corp-prod-pe-storage-cus`          | Maps storage to internal IP 10.10.4.4                |
| Private DNS Zone | `privatelink.blob.core.windows.net` | Auto-linked to Hub and Spoke                         |
| VPN Gateway      | `corp-prod-vpngw-cus`               | Point-to-Site VPN (provisioned)                      |
| Azure Bastion    | `corp-prod-bas-cus`                 | Browser-based VM access — no ports open              |
| Azure Firewall   | `corp-prod-afw-cus`                 | Outbound traffic inspection                          |
| Key Vault        | `corp-prod-kv-cus`                  | Secrets and certificates — RBAC + network restricted |
| Log Analytics    | `corp-prod-law-cus`                 | Central sink for all diagnostic data                 |
| Remote State     | `tfstatexxxxxxxx`                   | Terraform state — encrypted, versioned, lease-locked |

---

## Phase Roadmap

| Phase                          | Components                                                 | Status         |
| ------------------------------ | ---------------------------------------------------------- | -------------- |
| Phase 1 — Core Network         | NSGs, Hub VNet, Spoke VNet, VNet Peering                   | ✅ Complete    |
| Phase 2 — Secure Storage       | Storage Account, Private Endpoint, Private DNS             | ✅ Complete    |
| Phase 3 — Remote Access        | VPN Gateway provisioned, P2S cert pending                  | ✅ Provisioned |
| Phase 4 — Observability        | Log Analytics, Firewall Diagnostics, NSG Flow Logs         | ✅ Complete    |
| Phase 5 — Enterprise Hardening | Azure Bastion, Azure Firewall, Key Vault                   | ✅ Complete    |
| Phase 6 — State Management     | Remote State Backend                                       | ✅ Complete    |
| Phase 7 — Policy & Governance  | Azure Policy, DDoS Standard, Defender for Cloud, Terratest | 🔜 Planned     |

---

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) — authenticated via `az login`
- [Terraform CLI](https://developer.hashicorp.com/terraform/downloads) — v1.5.0 or later
- Contributor access on the target Azure subscription
- **Remote state storage bootstrapped before `terraform init`** (see [Bootstrap](#bootstrap-one-time-before-terraform-init) above)

---

_Portfolio project demonstrating production-grade Azure network engineering with Terraform — covering zero-trust network design, modular IaC patterns, private connectivity, remote state management, and enterprise security hardening._

![Resource Group](<../../images/Screenshot%20(338).png>)
![Network Topology](<../../images/Screenshot%20(339).png>)
![NSG Rules](<../../images/Screenshot%20(343).png>)
![Private Endpoint](<../../images/Screenshot%20(344).png>)
![DNS Zone](<../../images/Screenshot%20(345).png>)
![Firewall Logs](<../../images/Screenshot%20(346).png>)
![Bastion Access](<../../images/Screenshot%20(347).png>)
![Key Vault](<../../images/Screenshot%20(348).png>)
