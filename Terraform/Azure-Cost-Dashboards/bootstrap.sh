#!/bin/bash
# ============================================================
# ONE-TIME BOOTSTRAP SCRIPT
# Run this manually ONCE before running terragrunt init/apply
# Requires Azure CLI logged in: az login
# ============================================================

RESOURCE_GROUP="rg-terraform-state"
LOCATION="eastus"
# Generate a globally unique name
STORAGE_ACCOUNT="sttfstate$(openssl rand -hex 4)" 
CONTAINER="tfstate"

echo "Creating Resource Group: $RESOURCE_GROUP"
az group create --name $RESOURCE_GROUP --location $LOCATION

echo "Creating Storage Account: $STORAGE_ACCOUNT"
az storage account create \
  --name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --sku Standard_ZRS \
  --kind StorageV2 \
  --allow-blob-public-access false

echo "Creating Blob Container: $CONTAINER"
az storage container create \
  --name $CONTAINER \
  --account-name $STORAGE_ACCOUNT \
  --auth-mode login

echo "=========================================================="
echo "✅ BOOTSTRAP COMPLETE!"
echo ""
echo "To configure your local terminal, run the following commands:"
echo "=========================================================="
echo ""
echo "export TF_STATE_RG=\"$RESOURCE_GROUP\""
echo "export TF_STATE_SA=\"$STORAGE_ACCOUNT\""
echo "export TF_STATE_CONTAINER=\"$CONTAINER\""
echo ""
echo "NOTE: Add these to your ~/.bashrc or ~/.zshrc so you don't have to run them every time!"
echo "=========================================================="