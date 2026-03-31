#!/bin/bash
set -euo pipefail


LOG_DIR="$(dirname "$0")/logs"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="$LOG_DIR/deploy_${TIMESTAMP}.log"

# Tee all stdout to log file; also log stderr separately
exec > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2)

log_info()   { echo "[$(date +"%Y-%m-%d %H:%M:%S")] [INFO]   $*"; }
log_skip()   { echo "[$(date +"%Y-%m-%d %H:%M:%S")] [SKIP]   $1 already exists."; }
log_create() { echo "[$(date +"%Y-%m-%d %H:%M:%S")] [CREATE] $1..."; }
log_ok()     { echo "[$(date +"%Y-%m-%d %H:%M:%S")] [OK]     $1"; }
log_warn()   { echo "[$(date +"%Y-%m-%d %H:%M:%S")] [WARN]   $1"; }
log_fail()   {
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] [FAIL]   $1"
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] [FAIL]   See full log: $LOG_FILE"
    exit 1
}

# Trap any unexpected error and log it with the line number
trap 'echo "[$(date +"%Y-%m-%d %H:%M:%S")] [ERROR]  Unexpected failure at line $LINENO. Exit code: $?. See $LOG_FILE" >&2' ERR

# Run an az command, stream its output to the log, and surface errors clearly
# Usage: run_az <description> <az command...>
run_az() {
    local desc="$1"; shift
    log_info "Running: az $*"
    if ! az "$@" 2>&1 | tee -a "$LOG_FILE"; then
        log_fail "$desc"
    fi
}

exists() {
    "$@" >> "$LOG_FILE" 2>&1
    return $?
}

# ------------ SCRIPT START ------------

log_info "=========================================================="
log_info " Deploy started"
log_info " Log file : $LOG_FILE"
log_info "=========================================================="

# ------------ 1. INITIALIZATION ------------

read -p "Enter Subscription ID: " SUBSCRIPTION_ID
log_info "Setting subscription: $SUBSCRIPTION_ID"
run_az "Set subscription" account set --subscription "$SUBSCRIPTION_ID"
log_info "Ready to deploy in Subscription: $SUBSCRIPTION_ID"

# ------------ 2. VARIABLES ------------

RESOURCE_GROUP="RG1-VMs"
LOCATION="eastus"
VNET_NAME="Vnet-Prod"
VM_SUBNET_NAME="VM-Subnet"
BASTION_SUBNET_NAME="AzureBastionSubnet"
AV_SET_NAME="AvSet-Prod"
NSG_NAME="NSG-Prod"
LINUX_VM="Linux-Prod-01"
WIN_VM="Windows-Prod-01"
BASTION_NAME="Bastion-Prod"
BASTION_PIP="Bastion-PIP"

log_info "Variables loaded. RG=$RESOURCE_GROUP | Location=$LOCATION"

# ------------ 3. COST MANAGEMENT TAGS ------------

TAG_ENVIRONMENT="Production"
TAG_PROJECT="Prod-VM-Deployment"
TAG_OWNER="IT-Ops"
TAG_COST_CENTER="CC-1001"
TAG_AUTO_SHUTDOWN="2200-UTC"

TAGS=(
    "Environment=$TAG_ENVIRONMENT"
    "Project=$TAG_PROJECT"
    "Owner=$TAG_OWNER"
    "CostCenter=$TAG_COST_CENTER"
    "AutoShutdown=$TAG_AUTO_SHUTDOWN"
)

TAGS_ARG="${TAGS[*]}"

log_info "Cost tags defined:"
for tag in "${TAGS[@]}"; do
    log_info "  $tag"
done

# ------------ 4. CREDENTIALS ------------

read -p "Enter Admin Username: " ADMIN_USER
log_info "Admin username set: $ADMIN_USER"

SSH_KEY_PATH="$HOME/.ssh/azure_prod_rsa"

if [[ ! -f "${SSH_KEY_PATH}.pub" ]]; then
    log_info "No SSH key at ${SSH_KEY_PATH} — generating 4096-bit RSA key pair..."
    ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N "" -C "$ADMIN_USER@azure-prod"
    log_ok "SSH key pair created: $SSH_KEY_PATH"
else
    log_skip "SSH key '${SSH_KEY_PATH}'"
fi

SSH_PUBLIC_KEY=$(cat "${SSH_KEY_PATH}.pub")
log_info "SSH public key loaded from ${SSH_KEY_PATH}.pub"

echo ""
read -sp "Enter Admin Password (Windows VM only): " ADMIN_PASS
echo ""
log_info "Windows admin password received (not logged)"

# ------------ 5. PROVIDER REGISTRATION ------------

log_info "Registering resource providers..."
run_az "Register DevTestLab"  provider register --namespace Microsoft.DevTestLab
run_az "Register Compute"     provider register --namespace Microsoft.Compute
run_az "Register Network"     provider register --namespace Microsoft.Network
log_ok "Providers registered"

# ------------ 6. RESOURCE GROUP ------------

log_info "==> Resource Group"
if exists az group show --name "$RESOURCE_GROUP"; then
    log_skip "Resource Group '$RESOURCE_GROUP'"
else
    log_create "Resource Group '$RESOURCE_GROUP'"
    run_az "Create Resource Group" group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags $TAGS_ARG
    log_ok "Resource Group created"
fi

# ------------ 7. NSG ------------

log_info "==> Network Security Group"
if exists az network nsg show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$NSG_NAME"; then
    log_skip "NSG '$NSG_NAME'"
else
    log_create "NSG '$NSG_NAME'"
    run_az "Create NSG" network nsg create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$NSG_NAME" \
        --location "$LOCATION" \
        --tags $TAGS_ARG
    log_ok "NSG created"
fi

# ------------ 8. VNET & SUBNETS ------------

log_info "==> VNet"
if exists az network vnet show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VNET_NAME"; then
    log_skip "VNet '$VNET_NAME'"
else
    log_create "VNet '$VNET_NAME'"
    run_az "Create VNet" network vnet create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VNET_NAME" \
        --location "$LOCATION" \
        --address-prefix 10.0.0.0/16 \
        --subnet-name "$VM_SUBNET_NAME" \
        --subnet-prefix 10.0.10.0/24 \
        --tags $TAGS_ARG
    log_ok "VNet created"
fi

log_info "==> VM Subnet NSG Association"
CURRENT_NSG=$(az network vnet subnet show \
    --resource-group "$RESOURCE_GROUP" \
    --vnet-name "$VNET_NAME" \
    --name "$VM_SUBNET_NAME" \
    --query "networkSecurityGroup.id" -o tsv 2>/dev/null || echo "")

if [[ -n "$CURRENT_NSG" ]]; then
    log_skip "NSG already associated with '$VM_SUBNET_NAME'"
else
    log_create "Associating NSG with '$VM_SUBNET_NAME'"
    run_az "Associate NSG to subnet" network vnet subnet update \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$VM_SUBNET_NAME" \
        --nsg "$NSG_NAME"
    log_ok "NSG associated"
fi

log_info "==> Bastion Subnet"
if exists az network vnet subnet show \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$BASTION_SUBNET_NAME"; then
    log_skip "Subnet '$BASTION_SUBNET_NAME'"
else
    log_create "Subnet '$BASTION_SUBNET_NAME'"
    run_az "Create Bastion subnet" network vnet subnet create \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$BASTION_SUBNET_NAME" \
        --address-prefix 10.0.1.0/26
    log_ok "Bastion subnet created"
fi

# ------------ 9. BASTION PUBLIC IP ------------

log_info "==> Bastion Public IP"
if exists az network public-ip show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$BASTION_PIP"; then
    log_skip "Public IP '$BASTION_PIP'"
else
    log_create "Public IP '$BASTION_PIP'"
    run_az "Create Bastion PIP" network public-ip create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$BASTION_PIP" \
        --sku Standard \
        --location "$LOCATION" \
        --allocation-method Static \
        --tags $TAGS_ARG
    log_ok "Public IP created"
fi

# ------------ 10. AZURE BASTION ------------

log_info "==> Azure Bastion (can take 5-10 min if new)"
if exists az network bastion show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$BASTION_NAME"; then
    log_skip "Bastion '$BASTION_NAME'"
else
    log_create "Bastion '$BASTION_NAME'"
    run_az "Create Bastion" network bastion create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$BASTION_NAME" \
        --public-ip-address "$BASTION_PIP" \
        --vnet-name "$VNET_NAME" \
        --location "$LOCATION" \
        --tags $TAGS_ARG
    log_ok "Bastion created"
fi

# ------------ 11. AVAILABILITY SET ------------

log_info "==> Availability Set"
if exists az vm availability-set show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$AV_SET_NAME"; then
    log_skip "Availability Set '$AV_SET_NAME'"
else
    log_create "Availability Set '$AV_SET_NAME'"
    run_az "Create Availability Set" vm availability-set create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$AV_SET_NAME" \
        --location "$LOCATION" \
        --platform-fault-domain-count 2 \
        --platform-update-domain-count 2 \
        --tags $TAGS_ARG
    log_ok "Availability Set created"
fi

# ------------ 12. LINUX VM (SSH AUTH) ------------

log_info "==> Linux VM: $LINUX_VM"
if exists az vm show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$LINUX_VM"; then
    log_skip "VM '$LINUX_VM'"
else
    log_create "VM '$LINUX_VM' (SSH key auth)"
    run_az "Create Linux VM" vm create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$LINUX_VM" \
        --image Canonical:0001-com-ubuntu-minimal-focal:minimal-20_04-lts:latest \
        --size Standard_D2s_v3 \
        --admin-username "$ADMIN_USER" \
        --ssh-key-values "$SSH_PUBLIC_KEY" \
        --authentication-type ssh \
        --vnet-name "$VNET_NAME" \
        --subnet "$VM_SUBNET_NAME" \
        --availability-set "$AV_SET_NAME" \
        --storage-sku StandardSSD_LRS \
        --nsg "$NSG_NAME" \
        --public-ip-address "" \
        --location "$LOCATION" \
        --os-disk-name "$LINUX_VM-osdisk" \
        --tags $TAGS_ARG
    log_ok "Linux VM provisioned  |  ssh -i $SSH_KEY_PATH $ADMIN_USER@<private-ip>"
fi

log_info "==> Linux VM - Nginx Extension"
if exists az vm extension show \
        --resource-group "$RESOURCE_GROUP" \
        --vm-name "$LINUX_VM" \
        --name customScript; then
    log_skip "Nginx extension on '$LINUX_VM'"
else
    log_create "Installing Nginx on '$LINUX_VM'"
    run_az "Install Nginx" vm extension set \
        --resource-group "$RESOURCE_GROUP" \
        --vm-name "$LINUX_VM" \
        --name customScript \
        --publisher Microsoft.Azure.Extensions \
        --version 2.1 \
        --settings '{"commandToExecute":"sudo apt-get update && sudo apt-get install -y nginx"}'
    log_ok "Nginx installed"
fi

log_info "==> Linux VM - Azure Monitor Agent (Diagnostics)"
if exists az vm extension show \
        --resource-group "$RESOURCE_GROUP" \
        --vm-name "$LINUX_VM" \
        --name AzureMonitorLinuxAgent; then
    log_skip "Azure Monitor Agent on '$LINUX_VM'"
else
    log_create "Installing Azure Monitor Agent on '$LINUX_VM'"
    run_az "Install AMA Linux" vm extension set \
        --resource-group "$RESOURCE_GROUP" \
        --vm-name "$LINUX_VM" \
        --name AzureMonitorLinuxAgent \
        --publisher Microsoft.Azure.Monitor \
        --version 1.0 \
        --enable-auto-upgrade true
    log_ok "Azure Monitor Agent installed on Linux VM"
fi

log_info "==> Linux VM - Auto-Shutdown"
SHUTDOWN_RESOURCE="shutdown-computevm-$LINUX_VM"
if exists az resource show \
        --resource-group "$RESOURCE_GROUP" \
        --resource-type "Microsoft.DevTestLab/schedules" \
        --name "$SHUTDOWN_RESOURCE"; then
    log_skip "Auto-shutdown for '$LINUX_VM'"
else
    log_create "Auto-shutdown for '$LINUX_VM' at 22:00 UTC"
    run_az "Linux auto-shutdown" vm auto-shutdown \
        --resource-group "$RESOURCE_GROUP" \
        --name "$LINUX_VM" \
        --time 2200
    log_ok "Auto-shutdown configured"
fi

# ------------ 13. WINDOWS VM (PASSWORD AUTH) ------------

log_info "==> Windows VM: $WIN_VM"
if exists az vm show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$WIN_VM"; then
    log_skip "VM '$WIN_VM'"
else
    log_create "VM '$WIN_VM' (password auth)"
    run_az "Create Windows VM" vm create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$WIN_VM" \
        --image MicrosoftWindowsServer:WindowsServer:2019-Datacenter:latest \
        --size Standard_D2s_v3 \
        --admin-username "$ADMIN_USER" \
        --admin-password "$ADMIN_PASS" \
        --vnet-name "$VNET_NAME" \
        --subnet "$VM_SUBNET_NAME" \
        --availability-set "$AV_SET_NAME" \
        --storage-sku Premium_LRS \
        --nsg "$NSG_NAME" \
        --public-ip-address "" \
        --location "$LOCATION" \
        --os-disk-name "$WIN_VM-osdisk" \
        --tags $TAGS_ARG
    log_ok "Windows VM provisioned"
fi

log_info "==> Windows VM - IIS Extension"
if exists az vm extension show \
        --resource-group "$RESOURCE_GROUP" \
        --vm-name "$WIN_VM" \
        --name CustomScriptExtension; then
    log_skip "IIS extension on '$WIN_VM'"
else
    log_create "Installing IIS on '$WIN_VM'"
    run_az "Install IIS" vm extension set \
        --resource-group "$RESOURCE_GROUP" \
        --vm-name "$WIN_VM" \
        --name CustomScriptExtension \
        --publisher Microsoft.Compute \
        --version 1.10 \
        --settings '{"commandToExecute":"powershell.exe -ExecutionPolicy Unrestricted -Command Install-WindowsFeature -Name Web-Server -IncludeManagementTools"}'
    log_ok "IIS installed"
fi

log_info "==> Windows VM - Azure Monitor Agent (Diagnostics)"
if exists az vm extension show \
        --resource-group "$RESOURCE_GROUP" \
        --vm-name "$WIN_VM" \
        --name AzureMonitorWindowsAgent; then
    log_skip "Azure Monitor Agent on '$WIN_VM'"
else
    log_create "Installing Azure Monitor Agent on '$WIN_VM'"
    run_az "Install AMA Windows" vm extension set \
        --resource-group "$RESOURCE_GROUP" \
        --vm-name "$WIN_VM" \
        --name AzureMonitorWindowsAgent \
        --publisher Microsoft.Azure.Monitor \
        --version 1.0 \
        --enable-auto-upgrade true
    log_ok "Azure Monitor Agent installed on Windows VM"
fi

log_info "==> Windows VM - Auto-Shutdown"
SHUTDOWN_RESOURCE_WIN="shutdown-computevm-$WIN_VM"
if exists az resource show \
        --resource-group "$RESOURCE_GROUP" \
        --resource-type "Microsoft.DevTestLab/schedules" \
        --name "$SHUTDOWN_RESOURCE_WIN"; then
    log_skip "Auto-shutdown for '$WIN_VM'"
else
    log_create "Auto-shutdown for '$WIN_VM' at 22:00 UTC"
    run_az "Windows auto-shutdown" vm auto-shutdown \
        --resource-group "$RESOURCE_GROUP" \
        --name "$WIN_VM" \
        --time 2200
    log_ok "Auto-shutdown configured"
fi

# ------------ DONE ------------

log_info "=========================================================="
log_info " Deployment Complete (idempotent run)"

log_info " Cost tags applied to all resources:"
for tag in "${TAGS[@]}"; do
    log_info "   $tag"
done
log_info ""
log_info " Full deployment log saved to:"
log_info "   $LOG_FILE"
log_info "=========================================================="