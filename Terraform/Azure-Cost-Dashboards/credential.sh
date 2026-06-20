#!/bin/bash
# ==============================================================================
# Azure Cost Visibility Dashboard — Credential Setup Script
# Fetches Subscription ID, Tenant ID, creates a Service Principal,
# and exports all required environment variables for Terragrunt.
# ==============================================================================

set -e  # Stop immediately if any command fails

echo ""
echo "============================================================"
echo "  Azure Cost Visibility Dashboard — Credential Setup"
echo "============================================================"
echo ""

# ── Step 1: Check Azure CLI is installed and logged in ────────────────────────
echo "▶ Checking Azure CLI login status..."

if ! command -v az &> /dev/null; then
  echo ""
  echo "❌ ERROR: Azure CLI is not installed."
  echo "   Install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
  exit 1
fi

ACCOUNT=$(az account show 2>/dev/null)
if [ $? -ne 0 ]; then
  echo ""
  echo "❌ You are not logged into Azure CLI. Running az login..."
  az login
fi

echo "✅ Azure CLI is authenticated."
echo ""

# ── Step 2: Fetch Subscription ID and Tenant ID ───────────────────────────────
echo "▶ Fetching Subscription ID and Tenant ID..."

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)

echo ""
echo "   Subscription : $SUBSCRIPTION_NAME"
echo "   Subscription ID : $SUBSCRIPTION_ID"
echo "   Tenant ID       : $TENANT_ID"
echo ""

# ── Step 3: Create the Service Principal ─────────────────────────────────────
SP_NAME="sp-terraform-cost-dashboard"

echo "▶ Checking if Service Principal '$SP_NAME' already exists..."

EXISTING_SP=$(az ad sp list --display-name "$SP_NAME" --query "[0].appId" -o tsv 2>/dev/null)

if [ -n "$EXISTING_SP" ] && [ "$EXISTING_SP" != "None" ]; then
  echo ""
  echo "⚠️  Service Principal '$SP_NAME' already exists (appId: $EXISTING_SP)."
  echo "   Skipping creation. If you need a new secret, delete the existing SP first:"
  echo "   az ad sp delete --id $EXISTING_SP"
  echo ""
  CLIENT_ID=$EXISTING_SP
  echo "   Since the SP already exists, you need to provide the CLIENT_SECRET manually."
  echo "   If you have lost it, run:"
  echo "   az ad sp credential reset --id $EXISTING_SP"
  echo ""
  read -rsp "   Enter the existing CLIENT_SECRET (input hidden): " CLIENT_SECRET
  echo ""
else
  echo "▶ Creating Service Principal '$SP_NAME' with Owner role..."
  echo ""

  SP_OUTPUT=$(MSYS_NO_PATHCONV=1 az ad sp create-for-rbac \
  --name "$SP_NAME" \
  --role "Owner" \
  --scopes "/subscriptions/$SUBSCRIPTION_ID" \
  --output json)
  
  CLIENT_ID=$(echo "$SP_OUTPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['appId'])")
  CLIENT_SECRET=$(echo "$SP_OUTPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['password'])")

  echo "✅ Service Principal created successfully."
  echo ""
  echo "   ⚠️  IMPORTANT: Save this secret now — Azure will never show it again!"
  echo "   Client ID     : $CLIENT_ID"
  echo "   Client Secret : $CLIENT_SECRET"
  echo ""
fi

# ── Step 4: Export all environment variables ──────────────────────────────────
echo "▶ Exporting environment variables for this session..."
echo ""

export ARM_SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
export ARM_TENANT_ID="$TENANT_ID"
export ARM_CLIENT_ID="$CLIENT_ID"
export ARM_CLIENT_SECRET="$CLIENT_SECRET"

export TF_STATE_RG="rg-terraform-state"
export TF_STATE_SA="sttfstate62ed7ab4"
export TF_STATE_CONTAINER="tfstate"

echo "✅ The following variables are now active in this terminal session:"
echo ""
echo "   ARM_SUBSCRIPTION_ID = $ARM_SUBSCRIPTION_ID"
echo "   ARM_TENANT_ID       = $ARM_TENANT_ID"
echo "   ARM_CLIENT_ID       = $ARM_CLIENT_ID"
echo "   ARM_CLIENT_SECRET   = *** (hidden for security)"
echo "   TF_STATE_RG         = $TF_STATE_RG"
echo "   TF_STATE_SA         = $TF_STATE_SA"
echo "   TF_STATE_CONTAINER  = $TF_STATE_CONTAINER"
echo ""

# ── Step 5: Write to ~/.bashrc for persistence ────────────────────────────────
echo "▶ Do you want to save these to ~/.bashrc so they persist across sessions?"
echo "  (Recommended — means you never have to run this again)"
echo ""
read -rp "  Save to ~/.bashrc? (y/n): " SAVE_TO_BASHRC

if [[ "$SAVE_TO_BASHRC" =~ ^[Yy]$ ]]; then

  # Remove any existing entries to avoid duplicates
  sed -i '/# Azure Cost Dashboard Credentials/,/# END Azure Cost Dashboard Credentials/d' ~/.bashrc 2>/dev/null || true

  cat >> ~/.bashrc << EOF

# Azure Cost Dashboard Credentials
export ARM_SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
export ARM_TENANT_ID="$TENANT_ID"
export ARM_CLIENT_ID="$CLIENT_ID"
export ARM_CLIENT_SECRET="$CLIENT_SECRET"
export TF_STATE_RG="rg-terraform-state"
export TF_STATE_SA="sttfstate62ed7ab4"
export TF_STATE_CONTAINER="tfstate"
# END Azure Cost Dashboard Credentials
EOF

  echo ""
  echo "✅ Saved to ~/.bashrc. Run 'source ~/.bashrc' to load in new terminals."
else
  echo ""
  echo "⚠️  Not saved. These variables are active for this session only."
  echo "   Re-run this script when you open a new terminal."
fi

echo ""
echo "============================================================"
echo "  ✅ ALL DONE — You are ready to deploy!"
echo "============================================================"
echo ""
echo "  Next steps:"
echo ""
echo "  1. Navigate to the Dev environment:"
echo "     cd infra/environments/dev"
echo ""
echo "  2. Initialise Terragrunt:"
echo "     terragrunt run-all init"
echo ""
echo "  3. Preview what will be deployed:"
echo "     terragrunt run-all plan"
echo ""
echo "  4. Deploy Dev:"
echo "     terragrunt run-all apply"
echo ""
echo "============================================================"
echo ""