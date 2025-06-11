#!/bin/bash

# Script to create Azure Storage Account for Terraform Backend
# This script creates the necessary Azure resources to store Terraform state files remotely

set -e  # Exit on any error

# Configuration variables - Update these as needed
RESOURCE_GROUP_NAME="rg-terraform-state"
STORAGE_ACCOUNT_NAME="sttfstate$(date +%s)"  # Unique name with timestamp
CONTAINER_NAME="tfstate"
LOCATION="East US"  # Change to your preferred region
SUBSCRIPTION_ID=""  # Leave empty to use current subscription

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if Azure CLI is installed
check_azure_cli() {
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it first:"
        echo "  brew install azure-cli"
        exit 1
    fi
}

# Function to check if user is logged in to Azure
check_azure_login() {
    if ! az account show &> /dev/null; then
        print_error "You are not logged in to Azure. Please run:"
        echo "  az login"
        exit 1
    fi
}

# Function to set subscription if provided
set_subscription() {
    if [ -n "$SUBSCRIPTION_ID" ]; then
        print_info "Setting subscription to: $SUBSCRIPTION_ID"
        az account set --subscription "$SUBSCRIPTION_ID"
    else
        CURRENT_SUB=$(az account show --query name --output tsv)
        print_info "Using current subscription: $CURRENT_SUB"
    fi
}

# Function to create resource group
create_resource_group() {
    print_info "Creating resource group: $RESOURCE_GROUP_NAME"
    
    if az group show --name "$RESOURCE_GROUP_NAME" &> /dev/null; then
        print_warning "Resource group $RESOURCE_GROUP_NAME already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP_NAME" \
            --location "$LOCATION" \
            --tags purpose="terraform-backend" environment="shared"
        
        print_info "Resource group created successfully"
    fi
}

# Function to create storage account
create_storage_account() {
    print_info "Creating storage account: $STORAGE_ACCOUNT_NAME"
    
    # Check if storage account name is available
    if ! az storage account check-name --name "$STORAGE_ACCOUNT_NAME" --query nameAvailable --output tsv | grep -q "true"; then
        print_error "Storage account name $STORAGE_ACCOUNT_NAME is not available"
        # Generate a new unique name
        STORAGE_ACCOUNT_NAME="sttfstate$(openssl rand -hex 4)"
        print_info "Using alternative name: $STORAGE_ACCOUNT_NAME"
    fi
    
    az storage account create \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --https-only true \
        --min-tls-version TLS1_2 \
        --allow-blob-public-access false \
        --tags purpose="terraform-backend" environment="shared"
    
    print_info "Storage account created successfully"
}

# Function to create blob container
create_blob_container() {
    print_info "Creating blob container: $CONTAINER_NAME"
    
    # Get storage account key
    STORAGE_KEY=$(az storage account keys list \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --query '[0].value' \
        --output tsv)
    
    # Create container
    az storage container create \
        --name "$CONTAINER_NAME" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --account-key "$STORAGE_KEY" \
        --public-access off
    
    print_info "Blob container created successfully"
}

# Function to configure storage account security
configure_security() {
    print_info "Configuring storage account security settings"
    
    # Enable versioning
    az storage account blob-service-properties update \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --enable-versioning true
    
    # Enable soft delete for blobs (optional but recommended)
    az storage account blob-service-properties update \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --enable-delete-retention true \
        --delete-retention-days 30
    
    print_info "Security settings configured"
}

# Function to output Terraform backend configuration
output_terraform_config() {
    print_info "Terraform backend configuration:"
    echo
    echo "Add this to your Terraform configuration:"
    echo
    cat << EOF
terraform {
  backend "azurerm" {
    resource_group_name  = "$RESOURCE_GROUP_NAME"
    storage_account_name = "$STORAGE_ACCOUNT_NAME"
    container_name       = "$CONTAINER_NAME"
    key                  = "terraform.tfstate"
  }
}
EOF
    echo
    
    # Get storage account key for reference
    STORAGE_KEY=$(az storage account keys list \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --query '[0].value' \
        --output tsv)
    
    print_info "Storage Account Details:"
    echo "  Resource Group: $RESOURCE_GROUP_NAME"
    echo "  Storage Account: $STORAGE_ACCOUNT_NAME"
    echo "  Container: $CONTAINER_NAME"
    echo "  Location: $LOCATION"
    echo
    
    print_info "Environment variables for Terraform authentication:"
    echo "  export ARM_ACCESS_KEY=\"$STORAGE_KEY\""
    echo
    
    print_warning "Store the ARM_ACCESS_KEY securely. You'll need it for Terraform operations."
}

# Main execution
main() {
    print_info "Starting Azure Storage Account setup for Terraform backend"
    echo
    
    # Perform checks
    check_azure_cli
    check_azure_login
    set_subscription
    
    # Create resources
    create_resource_group
    create_storage_account
    create_blob_container
    configure_security
    
    # Output configuration
    output_terraform_config
    
    print_info "Setup completed successfully!"
    echo
    print_info "Next steps:"
    echo "1. Add the backend configuration to your Terraform files"
    echo "2. Run 'terraform init' to initialize the backend"
    echo "3. Set the ARM_ACCESS_KEY environment variable"
    echo
    print_info "Azure Portal link:"
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    echo "https://portal.azure.com/#@/resource/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT_NAME"
}

# Run main function
main "$@"
