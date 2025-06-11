#!/bin/bash

# =============================================================================
# Azure Terraform Backend Setup Script
# =============================================================================
# This script creates an Azure Storage Account with private endpoint and 
# blob container for storing Terraform state files securely.
#
# Prerequisites:
# - Azure CLI installed and authenticated (az login)
# - Sufficient permissions in the target subscription
# - Contributor access to create resources
# =============================================================================

set -e  # Exit on any error

# =============================================================================
# Configuration Variables
# =============================================================================

# Default values - modify these as needed
RESOURCE_GROUP_NAME="rg-terraform-backend"
STORAGE_ACCOUNT_NAME="sttfstate$(date +%s | tail -c 6)"  # Unique suffix
CONTAINER_NAME="tfstate"
LOCATION="East US"
VNET_NAME="vnet-terraform-backend"
SUBNET_NAME="subnet-storage"
PRIVATE_ENDPOINT_NAME="pe-storage-terraform"

# =============================================================================
# Helper Functions
# =============================================================================

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    echo "[ERROR] $1" >&2
    exit 1
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Not logged into Azure. Please run 'az login' first."
    fi
    
    # Check if subscription is set
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    if [ -z "$SUBSCRIPTION_ID" ]; then
        error "No active subscription found. Please run 'az account set --subscription <subscription-id>'"
    fi
    
    log "✅ Prerequisites check passed"
    log "   Subscription: $SUBSCRIPTION_ID"
}

# =============================================================================
# Main Setup Functions
# =============================================================================

create_resource_group() {
    log "Creating resource group: $RESOURCE_GROUP_NAME"
    
    az group create \
        --name "$RESOURCE_GROUP_NAME" \
        --location "$LOCATION" \
        --tags purpose="terraform-backend" environment="shared" \
        --output table
    
    log "✅ Resource group created successfully"
}

create_virtual_network() {
    log "Creating virtual network for private endpoints..."
    
    # Create VNet
    az network vnet create \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --name "$VNET_NAME" \
        --address-prefix "10.0.0.0/16" \
        --location "$LOCATION" \
        --output table
    
    # Create subnet for storage private endpoint
    az network vnet subnet create \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --vnet-name "$VNET_NAME" \
        --name "$SUBNET_NAME" \
        --address-prefixes "10.0.1.0/24" \
        --disable-private-endpoint-network-policies true \
        --output table
    
    log "✅ Virtual network and subnet created successfully"
}

create_storage_account() {
    log "Creating storage account: $STORAGE_ACCOUNT_NAME"
    
    # Create storage account with secure defaults
    az storage account create \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --name "$STORAGE_ACCOUNT_NAME" \
        --location "$LOCATION" \
        --sku "Standard_LRS" \
        --kind "StorageV2" \
        --access-tier "Hot" \
        --https-only true \
        --min-tls-version "TLS1_2" \
        --allow-blob-public-access false \
        --public-network-access Disabled \
        --tags purpose="terraform-backend" \
        --output table
    
    log "✅ Storage account created successfully"
}

create_blob_container() {
    log "Creating blob container: $CONTAINER_NAME"
    
    # Get storage account key
    STORAGE_ACCOUNT_KEY=$(az storage account keys list \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --query '[0].value' -o tsv)
    
    # Create container
    az storage container create \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --account-key "$STORAGE_ACCOUNT_KEY" \
        --name "$CONTAINER_NAME" \
        --public-access off \
        --output table
    
    log "✅ Blob container created successfully"
}

create_private_endpoint() {
    log "Creating private endpoint for storage account..."
    
    # Get storage account ID
    STORAGE_ACCOUNT_ID=$(az storage account show \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --name "$STORAGE_ACCOUNT_NAME" \
        --query id -o tsv)
    
    # Create private endpoint
    az network private-endpoint create \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --name "$PRIVATE_ENDPOINT_NAME" \
        --vnet-name "$VNET_NAME" \
        --subnet "$SUBNET_NAME" \
        --private-connection-resource-id "$STORAGE_ACCOUNT_ID" \
        --group-id "blob" \
        --connection-name "terraform-backend-connection" \
        --location "$LOCATION" \
        --output table
    
    log "✅ Private endpoint created successfully"
}

configure_private_dns() {
    log "Configuring private DNS zone for blob storage..."
    
    # Create private DNS zone
    az network private-dns zone create \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --name "privatelink.blob.core.windows.net" \
        --output table
    
    # Link DNS zone to VNet
    az network private-dns link vnet create \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --zone-name "privatelink.blob.core.windows.net" \
        --name "terraform-backend-dns-link" \
        --virtual-network "$VNET_NAME" \
        --registration-enabled false \
        --output table
    
    # Create DNS record for private endpoint
    PRIVATE_IP=$(az network private-endpoint show \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --name "$PRIVATE_ENDPOINT_NAME" \
        --query 'customDnsConfigs[0].ipAddresses[0]' -o tsv)
    
    az network private-dns record-set a create \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --zone-name "privatelink.blob.core.windows.net" \
        --name "$STORAGE_ACCOUNT_NAME" \
        --output table
    
    az network private-dns record-set a add-record \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --zone-name "privatelink.blob.core.windows.net" \
        --record-set-name "$STORAGE_ACCOUNT_NAME" \
        --ipv4-address "$PRIVATE_IP" \
        --output table
    
    log "✅ Private DNS configuration completed"
}

display_terraform_config() {
    log "Generating Terraform backend configuration..."
    
    # Get storage account key
    STORAGE_ACCOUNT_KEY=$(az storage account keys list \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --query '[0].value' -o tsv)
    
    cat << EOF

=============================================================================
🎉 Azure Terraform Backend Setup Complete!
=============================================================================

Your Terraform backend is now ready with the following configuration:

Backend Configuration (add to your Terraform configuration):
-----------------------------------------------------------

terraform {
  backend "azurerm" {
    resource_group_name  = "$RESOURCE_GROUP_NAME"
    storage_account_name = "$STORAGE_ACCOUNT_NAME"
    container_name       = "$CONTAINER_NAME"
    key                  = "terraform.tfstate"  # Change per environment
  }
}

Environment Variables (for authentication):
------------------------------------------
export ARM_SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
# Also set ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_TENANT_ID if using service principal

Resources Created:
-----------------
• Resource Group: $RESOURCE_GROUP_NAME
• Storage Account: $STORAGE_ACCOUNT_NAME (with private endpoint)
• Blob Container: $CONTAINER_NAME
• Virtual Network: $VNET_NAME
• Private Endpoint: $PRIVATE_ENDPOINT_NAME
• Private DNS Zone: privatelink.blob.core.windows.net

Security Features:
-----------------
✅ HTTPS only access
✅ TLS 1.2 minimum
✅ Public access disabled
✅ Private endpoint enabled
✅ Private DNS resolution

Next Steps:
----------
1. Initialize your Terraform project
2. Configure the backend as shown above
3. Run 'terraform init' to initialize the backend
4. Start building your Azure Landing Zone!

=============================================================================

EOF
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    log "Starting Azure Terraform Backend Setup..."
    log "This script will create secure infrastructure for Terraform state management"
    
    # Show configuration
    cat << EOF

Configuration:
--------------
Resource Group: $RESOURCE_GROUP_NAME
Storage Account: $STORAGE_ACCOUNT_NAME
Container: $CONTAINER_NAME
Location: $LOCATION
VNet: $VNET_NAME

EOF
    
    # Ask for confirmation
    read -p "Do you want to proceed with this configuration? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Setup cancelled by user"
        exit 0
    fi
    
    # Execute setup steps
    check_prerequisites
    create_resource_group
    create_virtual_network
    create_storage_account
    create_blob_container
    create_private_endpoint
    configure_private_dns
    display_terraform_config
    
    log "🚀 Setup completed successfully!"
}

# =============================================================================
# Script entry point
# =============================================================================

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi