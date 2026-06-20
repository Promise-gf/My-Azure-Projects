# Azure Cost Visibility Dashboard

A production-grade, self-healing FinOps pipeline built with Terraform, Terragrunt, and Python. Ingests daily Azure billing data, enriches it with business context, detects cost anomalies, and serves executive-level dashboards via Managed Grafana — all secured with Zero Trust networking, zero hardcoded credentials, and automated remediation.

> **Portfolio project demonstrating:** Infrastructure as Code, FinOps engineering, cloud security, CI/CD pipelines, and operational maturity on Microsoft Azure.

---

## The Problem This Solves

Engineering teams routinely overspend on cloud because billing data lives in Azure Cost Management — a tool finance understands but engineers rarely open. By the time a budget alert fires, the money is already spent.

This project solves that by building a fully automated pipeline that:

- Pulls daily actual cost CSVs from Azure Cost Management automatically
- Enriches raw billing records with department, team, and environment context
- Detects spend anomalies before they become budget overruns
- Heals itself when data goes stale — no on-call engineer required
- Serves role-scoped dashboards to every business unit via Managed Grafana with Azure AD SSO

---

## Architecture

```
Azure Cost Management
        │  (daily CSV push)
        ▼
  ZRS Storage Account ◄──────────────────────────────┐
  (cost-exports)                                      │
        │  (Event Grid trigger)                       │ (ZRS fallback cache)
        ▼                                             │
  Python Function App                                 │
  ├── cost_enricher      → Pydantic validation → Enriched JSON → ZRS (enriched-data)
  ├── budget_checker     → Circuit Breaker → Cost API → Phase 9 Auto-Stop
  ├── dlq_processor      → Retry / quarantine dead-lettered events
  ├── health             → Deep check (ZRS + KV) → 503 forces Auto-Heal
  ├── self_heal_trigger  → Forces Cost Export re-run on stale data alert
  ├── auto_shutdown      → Stops Dev environment at 7 PM UTC (cost saving)
  └── showback_api       → /api/showback/{department} via APIM (Phase 10)
        │
        ▼
  Log Analytics Workspace (DCR → CostEnrichmentLogs_CL)
        │
        ├── Stale Data Alert  → Action Group → self_heal_trigger (webhook)
        └── Anomaly Alert     → Action Group → Email / Teams
        │
        ▼
  Managed Grafana
  └── Executive Overview Dashboard (spend by dept, budget gauges, anomalies)
```

### 10-Layer Architecture

| Layer | Purpose |
|---|---|
| 1. Governance & Security | Tag enforcement policy, Microsoft Defender (VMs, Storage, App Services, Key Vault, Containers, ACR) |
| 2. Networking | Zero Trust VNet, Private Endpoints for Storage, Key Vault, and Grafana (Prod only) |
| 3. Storage (ZRS) | Zone-redundant blob storage, cost-exports container, enriched-data container, DLQ queue |
| 4. Key Vault | Secrets management, purge protection, RBAC authorization, zero hardcoded credentials |
| 5. Compute | Linux Function App, Docker container, Auto-Heal, deep health checks, Managed Identity |
| 6. IAM & RBAC | Least-privilege role assignments, Managed Identity, zero service principal passwords |
| 7. Self-Healing | DLQ processor, self_heal_trigger function, auto-shutdown, deep health endpoint |
| 8. Data Ingestion | AzAPI Cost Management export pushing daily Actual Cost CSVs |
| 9. Monitoring & Alerts | Log Analytics (90-day retention), App Insights, KQL anomaly detection, DCR structured logging |
| 10. Dashboards | Managed Grafana, Azure AD SSO, zone-redundant in Prod, dashboard-as-code |

---

## Key Engineering Decisions

### Why private endpoints instead of DDoS Standard?

Azure DDoS Standard costs approximately $2,944/month per protected public IP. This project explicitly removes all public IP addresses in production using Private Endpoints on Storage, Key Vault, and Grafana. There is no public surface to protect. DDoS Standard was excluded because the architecture neutralized the threat before it became a cost decision.

### Why no Terratest integration tests?

Terratest is designed for reusable Terraform modules being published to a private registry for other teams to consume. This is a standalone internal platform. The existing test stack — `pytest`, `ruff`, `bandit`, `checkov`, and `tflint` — provides strong safety guarantees at a fraction of the CI/CD runtime. Integration tests for the Python pipeline (`tests/integration/test_pipeline.py`) cover the end-to-end data flow without spinning up real Azure infrastructure in a sandbox subscription.

### Why Terraform/Terragrunt instead of Bicep?

Terragrunt's `run-all` and dependency graph management is the specific capability that enables clean multi-environment promotion (Dev → Prod) without duplicating configuration. Maintaining Bicep parity would double every PR, every test, and every drift detection check with no new capability. One tool, one standard.

### Why Python functions instead of Logic Apps?

Logic App workflows are defined in JSON generated by a visual designer — difficult to read, difficult to unit test, and difficult to review in a Pull Request. Every remediation and automation concern (self-healing, auto-shutdown, DLQ processing) lives in Python, in the same codebase, testable and reviewable like any other code change.

### Why ZRS instead of GRS?

Zone-Redundant Storage replicates data across three datacenters within the same Azure region — sufficient to survive a datacenter outage. Geo-Redundant Storage adds cross-region replication at higher cost. For an internal FinOps dashboard where a regional failover is an acceptable recovery scenario (documented in `docs/dr-plan.md`), ZRS provides the right durability at the right price.

---

## Project Structure

```
azure-cost-visibility/
├── .github/workflows/          # CI/CD pipelines (infra validation, app validation, deployment)
├── dashboards/                 # Grafana Dashboard JSON (dashboard-as-code)
├── docs/
│   ├── dr-plan.md              # Disaster Recovery Plan (RTO/RPO, GZRS failover strategy)
│   └── runbook.md              # Operational Runbook (2 AM alert response procedures)
├── infra/
│   ├── terragrunt.hcl          # Root config, remote state, Azure provider
│   ├── _envcommon/             # DRY shared inputs (Dev/Prod parity)
│   ├── modules/                # Reusable Terraform modules (one per concern)
│   └── environments/
│       ├── dev/                # Dev wrappers (Y1 SKU, $500 budget)
│       └── prod/               # Prod wrappers (EP2 SKU, $10k budget, VNet wired)
├── src/
│   ├── functions/              # Python Function App (7 functions)
│   └── shared/                 # Shared business logic (models, enrichment, alerting)
├── tests/
│   ├── test_models.py          # Unit tests (Pydantic thresholds)
│   ├── test_enrichment.py      # Unit tests (tag mapping, naming conventions)
│   └── integration/
│       └── test_pipeline.py    # End-to-end: CSV upload → enriched JSON verification
├── bootstrap.sh                # One-time remote state setup
├── Makefile                    # Developer shortcuts
└── README.md
```

---

## Terraform Module Reference

| Module | Resources Created | Key Outputs |
|---|---|---|
| `resource-group` | Azure Resource Group | `name`, `location`, `id` |
| `vnet` | VNet, Function Subnet, PE Subnet, NSG | `function_subnet_id`, `pe_subnet_id` |
| `storage-zrs` | ZRS Storage Account, 2 containers, DLQ queue, Private Endpoint | `storage_name`, `id`, `blob_endpoint` |
| `key-vault` | Key Vault (RBAC, purge protection), Private Endpoint | `kv_name`, `id`, `vault_uri` |
| `function-app-python` | App Service Plan (Y1/EP2), Linux Function App, MI RBAC | `principal_id`, `hostname`, `self_heal_function_url` |
| `monitoring-alerts` | Log Analytics (90d), App Insights, Action Groups, KQL Alerts | `connection_string`, `workspace_id` |
| `managed-grafana` | Grafana (zone-redundant), Private Endpoint, Data Sources | `endpoint`, `principal_id` |
| `cost-export` | AzAPI Cost Management daily CSV export | — |
| `azure-policy` | Policy Definition + Assignment (tag enforcement) | — |
| `defender` | Defender for VMs, Storage, Apps, KV, Containers, ACR | — |
| `dcr` | Data Collection Endpoint + Rule (`CostEnrichmentLogs_CL` schema) | `dce_endpoint`, `dcr_immutable_id`, `stream_name` |
| `auto-remediation` | Automation Account, Stop-OverBudget Runbook | `auto_stop_webhook_url` |
| `apim` | API Management (Consumption/Standard) | `gateway_url` |
| `container-app` | Container App Environment, KEDA-driven app (opt-in) | `container_app_id`, `fqdn` |

---

## CI/CD Pipeline

Four GitHub Actions workflows enforce quality gates at every stage.

### Pull Request Validation

**`ci-infra.yml`** — runs on every PR touching `infra/`
- TFLint — enforces Terraform best practices and AzureRM provider rules
- Checkov — static analysis for infrastructure security misconfigurations
- Terragrunt Plan — posts the full plan diff as a PR comment

**`ci-app.yml`** — runs on every PR touching `src/` or `tests/`
- Ruff — Python linting and formatting
- Bandit — Python security vulnerability scanning
- Mypy — static type checking
- Pytest — unit tests (80% coverage minimum enforced)
- Trivy — Docker container CVE scanning
- Integration tests — end-to-end pipeline validation

### Deployment

**`cd-infra.yml`** — triggers on merge to `main`
- Dev deploys automatically
- Prod requires a manual approval gate before any change is applied

**`cd-app.yml`** — triggers on merge to `main`
- Builds Docker container
- Pushes to Azure Container Registry
- Updates the Function App to pull the new container

---

## Prerequisites

Before deploying, ensure you have the following installed and configured.

| Tool | Version | Purpose |
|---|---|---|
| Terraform | >= 1.7.0 | Infrastructure provisioning |
| Terragrunt | >= 0.55.0 | Multi-environment orchestration |
| Azure CLI | >= 2.57.0 | Azure authentication |
| Python | >= 3.11 | Local function development and testing |
| Docker | >= 24.0 | Container builds |
| Make | Any | Developer shortcuts |

You also need:
- An Azure subscription with Owner role (required for policy and Defender assignments at subscription scope)
- A GitHub repository with Actions enabled
- The following GitHub Actions secrets configured: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`

---

## Deployment Guide

### Step 1 — Bootstrap remote state

Run this once before any Terraform commands. It creates the Storage Account that holds your Terraform state file and prints the environment variables you need.

```bash
chmod +x bootstrap.sh
./bootstrap.sh
```

Export the variables it outputs:

```bash
export TF_VAR_resource_group_name="..."
export TF_VAR_storage_account_name="..."
export TF_VAR_container_name="..."
export ARM_CLIENT_ID="..."
export ARM_TENANT_ID="..."
export ARM_SUBSCRIPTION_ID="..."
```

### Step 2 — Initialize Terragrunt

```bash
make init
```

This runs `terragrunt run-all init` across all modules in the target environment.

### Step 3 — Review the plan

```bash
# Dev environment
make plan ENV=dev

# Prod environment
make plan ENV=prod
```

Review the plan output carefully. Confirm the resource counts match expectations before applying.

### Step 4 — Deploy Dev

```bash
make apply ENV=dev
```

Terragrunt resolves the dependency graph automatically and applies modules in the correct order.

### Step 5 — Deploy Prod

```bash
make apply ENV=prod
```

Prod deployment requires manual confirmation at the terminal prompt. The CI/CD pipeline additionally requires a GitHub Actions manual approval gate.

### Step 6 — Deploy the Python application

```bash
make docker-build
make docker-push
make function-update
```

Or push to `main` and let `cd-app.yml` handle it automatically.

### Step 7 — Verify the deployment

```bash
# Run the full test suite including integration tests
make test

# Check the health endpoint
curl https://<your-function-hostname>/api/health
```

A `200 OK` response confirms the Function App can reach both ZRS Storage and Key Vault successfully.

---

## Local Development

```bash
# Install Python dependencies
pip install -r src/functions/requirements.txt

# Run unit tests
make test-unit

# Run integration tests (requires Azure credentials)
make test-integration

# Run all linters
make lint

# Run security scan
make security
```

---

## Deployment Evidence

> Screenshots will be added following initial deployment.

- [ ] Terragrunt apply output (Dev)
- [ ] Terragrunt apply output (Prod)
- [ ] Grafana executive dashboard with live cost data
- [ ] Application Insights showing function invocations
- [ ] Azure Policy compliance report (tag enforcement active)
- [ ] Defender for Cloud recommendations dashboard
- [ ] Private Endpoints attached in Azure Portal
- [ ] Stale data alert firing and self-heal trigger executing

---

## Operational Resources

| Document | Contents |
|---|---|
| `docs/dr-plan.md` | RTO/RPO targets, GZRS failover strategy, regional outage response |
| `docs/runbook.md` | Step-by-step procedures for every alert scenario, 2 AM response guide |

---

## Future Phases

| Phase | Description | Cost Impact |
|---|---|---|
| Phase 9 — FinOps Automation | Auto-stop non-production resources when budget hits 100% | Saves money |
| Phase 10 — Showback API | APIM-fronted `/api/showback/{department}` endpoint for chargeback integrations | Neutral (pennies per 1,000 calls) |
| Phase 11 — Container Apps | Replace EP2 Function App with KEDA-driven Container App scaling to zero | Saves ~$200/month |

---

## Technologies Used

**Infrastructure:** Terraform, Terragrunt, Azure Resource Manager, AzAPI provider

**Compute:** Azure Functions (Python 3.11), Docker, Azure Container Registry

**Storage & Messaging:** Azure Blob Storage (ZRS), Azure Storage Queue

**Security:** Azure Key Vault, Microsoft Defender for Cloud, Azure Policy, Private Endpoints, Managed Identity

**Observability:** Log Analytics, Application Insights, Azure Monitor, Data Collection Rules, KQL

**Dashboards:** Managed Grafana, Azure AD SSO

**CI/CD:** GitHub Actions, TFLint, Checkov, Ruff, Bandit, Mypy, Pytest, Trivy

**Data:** Azure Cost Management, Pydantic V2, azure-monitor-ingestion

---

## License

MIT