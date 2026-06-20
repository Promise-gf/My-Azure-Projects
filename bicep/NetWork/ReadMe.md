# 🏗️ Azure Secure Network Architecture — Hub & Spoke with Private Endpoints & VPN Gateway

![Azure](https://img.shields.io/badge/Azure-Infrastructure-0078D4?style=for-the-badge&logo=microsoftazure&logoColor=white)
![Bicep](https://img.shields.io/badge/IaC-Bicep-FF6F00?style=for-the-badge&logo=azuredevops&logoColor=white)
![Architecture](https://img.shields.io/badge/Architecture-Hub_and_Spoke-28A745?style=for-the-badge)
![Zero Trust](https://img.shields.io/badge/Security-Zero_Trust-DC3545?style=for-the-badge)

> **A production-grade, modular Azure network infrastructure built entirely with Bicep IaC — designed around a real-world financial services security problem.**

---

## 📖 Table of Contents

- [Real-World Problem](#-real-world-problem)
- [The Solution](#-the-solution)
- [Architecture Overview](#-architecture-overview)
- [Resources Deployed](#-resources-deployed)
- [Project Structure](#-project-structure)
- [Prerequisites](#-prerequisites)
- [Deployment Guide](#-deployment-guide)
- [Security Highlights](#-security-highlights)
- [Bicep Engineering Highlights](#-bicep-engineering-highlights)
- [Phase Roadmap](#-phase-roadmap)
- [Screenshots](#-screenshots)

---

## 🚨 Real-World Problem

### Scenario: A Digital Lending Company with Critical Security Gaps

**CreditBridge** is a Nigerian digital lending startup that disburses loans to thousands of customers monthly through a mobile app. Their engineering team built their initial Azure infrastructure rapidly during a funding sprint — trading security and governance for speed to market. Six months later, a routine third-party security audit exposed multiple critical vulnerabilities:

- Their **Storage Account** — containing customer BVN data, loan agreements, and KYC documents — was reachable from any IP address on the public internet, secured only by a rotating access key stored in a `.env` file on a developer's laptop.
- Remote engineers and third-party contractors were accessing internal application servers through **Management Ports (SSH port 22) left open to the entire internet**, protected only by weak password authentication.
- All traffic between their Node.js application servers and the Storage Account was **travelling over the public internet** — exposing sensitive financial data to potential interception and man-in-the-middle attacks.
- Multiple engineers had been provisioning resources manually through the Azure Portal for months, resulting in **chaotic, inconsistent naming** (`new-vnet`, `vnet-2-final`, `PROD-Network-USE`) that made automation and auditing impossible.
- An upcoming **CBN (Central Bank of Nigeria) compliance audit** and obligations under **NDPR (Nigeria Data Protection Regulation)** required that all customer Personally Identifiable Information (PII) never traverse the public internet, and that all infrastructure be documented, version-controlled, and reproducible.

The audit report concluded with one critical finding: the storage account holding customer financial data had received **847 unauthorized access attempts** in the past 30 days alone. The company had been lucky. A breach would have triggered regulatory sanctions and destroyed customer trust overnight.

**The engineering challenge: How do you redesign a cloud network so that sensitive resources are completely invisible to the public internet, enforce strict traffic boundaries between application tiers, automate naming governance, and allow authorised engineers to access it securely — all defined as repeatable, auditable code?**

---

## ✅ The Solution

This project implements a **production-grade, zero-trust Hub-and-Spoke network architecture on Microsoft Azure** using fully modular Bicep Infrastructure as Code. It directly addresses every vulnerability CreditBridge faced:

| Problem | Solution Implemented |
|---------|----------------------|
| Storage Account reachable from public internet | Private Endpoint — blob traffic never leaves the Microsoft backbone network |
| SSH ports exposed to the internet | Point-to-Site VPN Gateway with OpenVPN certificate authentication — no public ports open |
| Sensitive data traversing public internet | Private DNS Zones resolve storage to an internal RFC 1918 IP address automatically |
| No traffic segmentation between app tiers | Dedicated subnets per tier with dynamically generated, tiered NSG rules |
| Inconsistent resource naming and manual provisioning | Centralized Naming Module generates 100% standardized, compliant names across all resources |
| Monolithic, hard-to-maintain infrastructure code | Fully decoupled Bicep modules — teams can update NSG rules without touching VNet or VPN code |
| No audit trail or monitoring | Azure Monitor + Log Analytics workspace with diagnostic settings on all critical resources |
| Secrets and certificates stored insecurely | Azure Key Vault with RBAC authorization and network-restricted access |

After deploying this architecture, **the Storage Account has no public endpoint**. A malicious actor scanning the internet would find nothing. Internal services communicate exclusively over private RFC 1918 address space. Remote engineers connect through an encrypted VPN tunnel before accessing any resource. Every piece of infrastructure is version-controlled, modular, and reproducible from a single command.

---

## 🏛️ Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                            AZURE SUBSCRIPTION                                │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                     HUB VNET (10.10.0.0/16)                          │  │
│  │                                                                        │  │
│  │  ┌──────────────┐   ┌──────────────┐   ┌──────────────────────────┐  │  │
│  │  │   snet-web   │   │   snet-app   │   │      snet-database       │  │  │
│  │  │10.10.1.0/24  │──▶│10.10.2.0/24  │──▶│      10.10.3.0/24        │  │  │
│  │  │  [NSG-web]   │   │  [NSG-app]   │   │       [NSG-db]           │  │  │
│  │  │ HTTP/HTTPS   │   │ Port 8080    │   │   SQL Port 1433 only     │  │  │
│  │  │ from Internet│   │ from Web only│   │   from App subnet only   │  │  │
│  │  └──────────────┘   └──────────────┘   └──────────────────────────┘  │  │
│  │                                                                        │  │
│  │  ┌──────────────┐   ┌──────────────┐   ┌──────────────────────────┐  │  │
│  │  │   snet-pe    │   │AzureBastion  │   │    GatewaySubnet         │  │  │
│  │  │10.10.4.0/24  │   │  Subnet      │   │   10.10.255.224/27       │  │  │
│  │  │[pe-storage]  │   │10.10.254.0/26│   │  [VPN Gateway - VpnGw1] │  │  │
│  │  │IP: 10.10.4.4 │   │[Azure Bastion│   │  OpenVPN / Cert Auth     │  │  │
│  │  │(private only)│   │  No SSH/RDP  │   │                          │  │  │
│  │  │              │   │  exposed]    │   │                          │  │  │
│  │  └──────────────┘   └──────────────┘   └──────────────────────────┘  │  │
│  │                                                                        │  │
│  │  ┌──────────────────────────────────────────────────────────────────┐ │  │
│  │  │  AzureFirewallSubnet (10.10.253.0/26)                           │ │  │
│  │  │  [Azure Firewall — inspects all outbound traffic]               │ │  │
│  │  │  [Diagnostic logs → Log Analytics Workspace]                    │ │  │
│  │  └──────────────────────────────────────────────────────────────────┘ │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                  VNet Peering (Gateway Transit: Enabled) ↕                    │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                    SPOKE VNET (10.20.0.0/16)                          │  │
│  │              snet-workload (10.20.1.0/24) [NSG-secondary]            │  │
│  │         Isolated workload network — routes through Hub VPN Gateway    │  │
│  │              (Gateway Transit saves ~$150/month vs 2nd Gateway)       │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │  Storage Account (Public Network Access: DISABLED)                    │  │
│  │  Resolved internally as: privatelink.blob.core.windows.net           │  │
│  │  Private IP: 10.10.4.4 — invisible to public internet                │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────────┐   │
│  │  Key Vault       │  │  Log Analytics   │  │  Private DNS Zone        │   │
│  │  (RBAC + Network │  │  Workspace       │  │  Linked to Hub & Spoke   │   │
│  │   Restricted)    │  │  (All diagnostics│  │  Auto-resolves storage   │   │
│  │                  │  │   stream here)   │  │  to private IP           │   │
│  └──────────────────┘  └──────────────────┘  └──────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────────────┘
                    ↑
          VPN Tunnel (OpenVPN / Point-to-Site)
                    ↑
     Remote Engineer / Contractor (192.168.10.0/24)
     [Connects via VPN first — then accesses resources privately]
```

### Traffic Flow Summary

| Traffic Type | Path | Public Internet? |
|---|---|---|
| User → Web App | Internet → snet-web (80/443) | ✅ Intentional |
| Web → App Server | snet-web → snet-app (8080) | ❌ Private only |
| App → Database | snet-app → snet-db (1433) | ❌ Private only |
| App → Storage | snet-app → Private Endpoint (10.10.4.4) | ❌ Private only |
| Engineer → VMs | VPN tunnel → private subnet SSH | ❌ Private only |
| Spoke → Hub resources | VNet Peering → Gateway Transit | ❌ Private only |

---

## 📦 Resources Deployed

| Resource | Generated Name Example | Purpose |
|----------|------------------------|---------|
| Naming Module | `modules/naming.bicep` | Standardizes all resource names from prefix + environment + location |
| Virtual Network (Hub) | `corp-dev-vnet-hub-cus` | Core hub network housing all shared infrastructure |
| Virtual Network (Spoke) | `corp-dev-vnet-spoke-cus` | Isolated spoke for separate workload teams |
| VNet Peering | `peer-hub-to-spoke` / `peer-spoke-to-hub` | Bidirectional routing with gateway transit enabled |
| NSG (Web Tier) | `corp-dev-nsg-web-cus` | Allows HTTP/HTTPS from Internet; denies everything else |
| NSG (App Tier) | `corp-dev-nsg-app-cus` | Allows port 8080 from Web subnet only; denies Internet |
| NSG (Database Tier) | `corp-dev-nsg-db-cus` | Allows SQL 1433 from App subnet only; denies all else |
| NSG (Spoke) | `corp-dev-nsg-spoke-cus` | Allows inbound only from Hub VNet prefix |
| Storage Account | `corpdevstxxxxxxxx` | Secure blob storage — public access fully disabled |
| Private Endpoint | `corp-dev-pe-storage-cus` | Maps storage to internal IP 10.10.4.4 |
| Private DNS Zone | `privatelink.blob.core.windows.net` | Auto-linked to Hub and Spoke for seamless internal resolution |
| VPN Gateway | `corp-dev-vpngw-cus` | Point-to-Site VPN for secure remote engineer access |
| Public IP (VPN) | `corp-dev-pip-vpngw-cus` | Static IP for VPN Gateway public endpoint |
| Azure Bastion | `corp-dev-bas-cus` | Browser-based VM access — no SSH/RDP ports exposed |
| Azure Firewall | `corp-dev-afw-cus` | Inspects and controls all outbound traffic from Hub |
| Key Vault | `corp-dev-kv-cus` | Stores VPN certificates and secrets — network restricted |
| Log Analytics Workspace | `corp-dev-law-cus` | Central monitoring — firewall logs, NSG flow logs, diagnostics |

---

## 📁 Project Structure

This project follows **Strict Module Decoupling**. `main.bicep` is a pure orchestrator — it wires modules together and passes resource IDs. The `modules/` folder contains self-contained, reusable components with no knowledge of each other or the project's naming conventions.

```text
azure-secure-hub-spoke/
├── main.bicep                    # Orchestrator: calls modules, passes outputs as inputs
├── parameters.dev.json           # Dev environment: VPN/Bastion/Firewall toggles for cost control
│
└── modules/
    ├── naming.bicep              # Naming engine: generates standardized names from prefix+env+location
    ├── nsg.bicep                 # Dynamic NSG: accepts tierType string, generates tiered security rules
    ├── vnet.bicep                # VNet builder: subnets, NSG associations, gateway subnet control
    ├── peering.bicep             # VNet Peering: bidirectional hub-spoke with gateway transit
    ├── endpoints.bicep           # Private Endpoint + DNS Zone + A-Record — fully automated
    ├── vpn.bicep                 # VPN Gateway: VpnGw1, OpenVPN, certificate authentication
    ├── bastion.bicep             # Azure Bastion: browser-based access, no open ports
    ├── firewall.bicep            # Azure Firewall: outbound inspection + diagnostic streaming
    ├── keyvault.bicep            # Key Vault: RBAC-enabled, network-restricted secret store
    └── loganalytics.bicep        # Log Analytics: central workspace for all diagnostic data
```

---

## ✅ Prerequisites

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) installed and authenticated (`az login`)
- An active Azure subscription with **Contributor** access on the target Resource Group
- [Bicep CLI](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/install) installed (or use the Azure CLI built-in version)

### Generate a VPN Root Certificate (PowerShell — Windows)
> Only required if `deployVpn` is set to `true` in your parameters file.

```powershell
# Generate self-signed root certificate
$rootCert = New-SelfSignedCertificate `
  -Type Custom -KeySpec Signature `
  -Subject "CN=CreditBridgeVPNRoot" `
  -KeyExportPolicy Exportable `
  -HashAlgorithm sha256 -KeyLength 2048 `
  -CertStoreLocation "Cert:\CurrentUser\My" `
  -KeyUsageProperty Sign -KeyUsage CertSign

# Export Base64 public key — paste this into your parameters file
[Convert]::ToBase64String($rootCert.RawData)
```

---

## 🚀 Deployment Guide

### Step 1 — Clone the Repository
```bash
git clone https://github.com/your-username/azure-secure-hub-spoke-bicep.git
cd azure-secure-hub-spoke-bicep
```

### Step 2 — Configure Parameters
Open `parameters.dev.json` and update the required values:
```json
{
  "parameters": {
    "prefix":               { "value": "corp" },
    "environment":          { "value": "dev" },
    "deployVpn":            { "value": false },
    "deployBastion":        { "value": true },
    "deployFirewall":       { "value": true },
    "deployLogAnalytics":   { "value": true },
    "deployKeyVault":       { "value": true },
    "deployPrivateEndpoints": { "value": true }
  }
}
```

> 💡 **Cost tip:** Set `deployVpn`, `deployFirewall`, and `deployBastion` to `false` for a lightweight dev deployment. The VPN Gateway alone costs ~$140/month.

### Step 3 — Create Resource Group
```bash
az group create \
  --name rg-corp-network-dev \
  --location centralus
```

### Step 4 — Validate with What-If (Dry Run)
```bash
az deployment group what-if \
  --resource-group rg-corp-network-dev \
  --template-file main.bicep \
  --parameters parameters.dev.json
```

### Step 5 — Deploy
```bash
az deployment group create \
  --resource-group rg-corp-network-dev \
  --template-file main.bicep \
  --parameters parameters.dev.json
```

### Step 6 — Verify Zero-Trust Setup
```bash
# Confirm storage has no public endpoint
az storage account show \
  --name corpdevstxxxxxxxx \
  --resource-group rg-corp-network-dev \
  --query "{PublicAccess:properties.allowBlobPublicAccess, NetworkDefault:properties.networkAcls.defaultAction}"

# Confirm Private Endpoint resolved to internal IP
az network private-endpoint show \
  --name corp-dev-pe-storage-cus \
  --resource-group rg-corp-network-dev \
  --query "{FQDN:properties.customDnsConfigs[0].fqdn, PrivateIP:properties.customDnsConfigs[0].ipAddresses[0]}"

# Review NSG rules on database subnet
az network nsg show \
  --name corp-dev-nsg-db-cus \
  --resource-group rg-corp-network-dev \
  --query "properties.securityRules[].{Name:name,Access:access,Priority:priority,Direction:direction}" \
  --output table
```

---

## 🔒 Security Highlights

### 1. Zero Public Exposure on Storage
The Storage Account is deployed with `allowBlobPublicAccess: false` and `networkAcls.defaultAction: Deny`. It is reachable only via the Private Endpoint IP `10.10.4.4` inside `snet-pe`. An external port scan finds nothing.

### 2. Tiered Zero-Trust Micro-Segmentation
Traffic cannot jump tiers. The `nsg.bicep` module enforces hard boundaries using source CIDR whitelisting:
- **Web tier** — accepts HTTP/HTTPS from Internet only; DenyAll on everything else
- **App tier** — accepts port 8080 from Web subnet CIDR only; Internet is fully blocked
- **Database tier** — accepts SQL port 1433 from App subnet CIDR only; denies Web and Internet entirely
- **Spoke tier** — accepts traffic only from the Hub VNet address space

### 3. No Management Ports Open to the Internet
SSH (port 22) and RDP (port 3389) are never exposed publicly. Engineers access VMs through **Azure Bastion** (browser-based, no open ports) or through the **Point-to-Site VPN** tunnel — arriving on the private `192.168.10.0/24` pool, which is then whitelisted in NSG rules.

### 4. Enforced Deployment Dependencies
The Firewall module will only deploy if Log Analytics is also enabled (`deployFirewall && deployLogAnalytics`). This prevents a firewall ever being deployed without a destination for its audit logs — a compliance requirement under most security frameworks.

### 5. Gateway Transit Cost Optimization
Instead of deploying a second VPN Gateway in the Spoke VNet (~$140/month additional cost), the peering module configures `allowGatewayTransit: true` on the Hub side and `useRemoteGateways: true` on the Spoke side. Remote engineers connect once to the Hub Gateway and Azure routes them into the Spoke automatically.

### 6. Secrets Never in Outputs or Parameters
The Log Analytics workspace key is never exposed as a Bicep output (which is stored in plain text in deployment history). The VPN root certificate is passed as a `@secure()` parameter. Long-term secret storage is handled by the Key Vault module with RBAC authorization — no access key policies.

---

## 🧠 Bicep Engineering Highlights

### 1. Dynamic NSG Rule Generation
Rather than four separate, hard-coded NSG files, a single `modules/nsg.bicep` accepts a `tierType` string (`'web'`, `'app'`, `'database'`, `'secondary'`) and generates the correct security rules at deploy time using ternary logic. Adding a new tier requires one new condition — no new files.

### 2. Centralized Naming Engine
`modules/naming.bicep` accepts `prefix`, `environment`, and `location` and outputs every resource name used in the project. No module constructs its own name. This means naming convention changes happen in exactly one file.

```bicep
// Every resource name in the project flows from here
output vnet1      string = '${prefix}-${env}-vnet-hub-${loc}'
output nsgWeb     string = '${prefix}-${env}-nsg-web-${loc}'
output firewall   string = '${prefix}-${env}-afw-${loc}'
output keyVault   string = '${prefix}-${env}-kv-${loc}'
```

### 3. Feature Toggle Architecture
Every optional component (VPN, Bastion, Firewall, Key Vault, Log Analytics, Private Endpoints) is controlled by a boolean parameter. This makes the same template deployable as a cheap dev environment or a full production stack — without editing template code.

```bicep
param deployVpn           bool = true
param deployBastion       bool = true
param deployFirewall      bool = true
param deployLogAnalytics  bool = true
param deployKeyVault      bool = true
```

### 4. Decoupled Module Design
Modules have no knowledge of the project's naming conventions, other modules, or each other. `main.bicep` resolves all names via the naming module and passes flat strings and IDs downward. You can drop any module into a completely different project and it works without modification.

### 5. Safe Conditional Output Pattern
Bicep conditional modules return `module | null`. All optional module outputs are safely accessed using `any()` to bypass the compiler's null check while preserving runtime intent:
```bicep
output firewallId string = (deployFirewall && deployLogAnalytics) ? any(firewall).outputs.firewallId : ''
```

---

## 🗺️ Phase Roadmap

| Phase | Status | Components |
|-------|--------|------------|
| Phase 1 — Core Network | ✅ Complete | NSGs, Hub VNet, Spoke VNet, VNet Peering |
| Phase 2 — Secure Storage | ✅ Complete | Storage Account, Private Endpoint, Private DNS |
| Phase 3 — Remote Access | ✅ Complete | VPN Gateway, Point-to-Site, Certificate Auth |
| Phase 4 — Observability | ✅ Complete | Log Analytics, Firewall Diagnostics |
| Phase 5 — Enterprise Hardening | ✅ Complete | Azure Bastion, Azure Firewall, Key Vault |
| Phase 6 — Policy & Governance | 🔜 Planned | Azure Policy, DDoS Standard, Defender for Cloud |

---

## 📸 Screenshots

> _Add screenshots after successful deployment_

| Screenshot | Description |
|-----------|-------------|
| `screenshots/01-resource-group.png` | All resources deployed successfully across modules |
| `screenshots/02-network-topology.png` | Azure Network Topology view showing Hub-Spoke routing |
| `screenshots/03-nsg-db-rules.png` | Database NSG — SQL 1433 allowed from App subnet only |
| `screenshots/04-private-endpoint.png` | Private Endpoint mapped to internal IP 10.10.4.4 |
| `screenshots/05-dns-zone.png` | Private DNS Zone linked to both Hub and Spoke VNets |
| `screenshots/06-firewall-logs.png` | Azure Firewall streaming logs to Log Analytics |
| `screenshots/07-bastion-access.png` | Browser-based VM access via Azure Bastion |

---

## 👤 Author

Built as a portfolio project demonstrating production-grade Azure network engineering using Bicep IaC — covering zero-trust network design, modular infrastructure patterns, private connectivity, and enterprise security hardening.

> If you are a recruiter or hiring manager reviewing this project, feel free to reach out. I am open to Azure Cloud Engineer, Infrastructure Engineer, and DevOps Engineer roles.

---

*This project is for educational and portfolio purposes. Resource names, IP ranges, and company names used are fictional.*