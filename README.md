# Azure Storage Account Setup for Terraform Backend

This directory contains scripts to create an Azure Storage Account for storing Terraform state files remotely.

## Prerequisites

1. **Azure CLI installed**: 
   - macOS: `brew install azure-cli`
   - Windows: Download from [Microsoft Docs](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)

2. **Azure CLI logged in**: `az login`

3. **Appropriate permissions**: You need permissions to create resource groups and storage accounts in your Azure subscription

## Scripts

### For macOS/Linux: `setup-terraform-backend.sh`

```bash
# Make executable and run
chmod +x setup-terraform-backend.sh
./setup-terraform-backend.sh
```

### For Windows: `setup-terraform-backend.ps1`

```powershell
# Run in PowerShell
.\setup-terraform-backend.ps1
```

## Manual Azure CLI Commands

If you prefer to run commands manually:

```bash
# Set variables
RESOURCE_GROUP_NAME="rg-terraform-state"
STORAGE_ACCOUNT_NAME="sttfstate$(date +%s)"
CONTAINER_NAME="tfstate"
LOCATION="East US"

# Create resource group
az group create \
    --name $RESOURCE_GROUP_NAME \
    --location $LOCATION \
    --tags purpose="terraform-backend" environment="shared"

# Create storage account
az storage account create \
    --name $STORAGE_ACCOUNT_NAME \
    --resource-group $RESOURCE_GROUP_NAME \
    --location $LOCATION \
    --sku Standard_LRS \
    --kind StorageV2 \
    --access-tier Hot \
    --https-only true \
    --min-tls-version TLS1_2 \
    --allow-blob-public-access false \
    --tags purpose="terraform-backend" environment="shared"

# Get storage account key
STORAGE_KEY=$(az storage account keys list \
    --resource-group $RESOURCE_GROUP_NAME \
    --account-name $STORAGE_ACCOUNT_NAME \
    --query '[0].value' \
    --output tsv)

# Create blob container
az storage container create \
    --name $CONTAINER_NAME \
    --account-name $STORAGE_ACCOUNT_NAME \
    --account-key $STORAGE_KEY \
    --public-access off

# Enable versioning (recommended for state files)
az storage account blob-service-properties update \
    --resource-group $RESOURCE_GROUP_NAME \
    --account-name $STORAGE_ACCOUNT_NAME \
    --enable-versioning true

# Enable soft delete (optional but recommended)
az storage account blob-service-properties update \
    --resource-group $RESOURCE_GROUP_NAME \
    --account-name $STORAGE_ACCOUNT_NAME \
    --enable-delete-retention true \
    --delete-retention-days 30
```

## What the Script Creates

1. **Resource Group**: `rg-terraform-state` (default name)
2. **Storage Account**: With a unique name like `sttfstate1234567890`
3. **Blob Container**: `tfstate` for storing state files
4. **Security Settings**: 
   - HTTPS only
   - TLS 1.2 minimum
   - No public blob access
   - Versioning enabled
   - Soft delete enabled (30 days retention)

## Terraform Backend Configuration

After running the script, add this to your Terraform configuration:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "your-storage-account-name"
    container_name       = "tfstate"
    key                  = "terraform.tfstate"
  }
}
```

## Authentication Options

### Option 1: Access Key (Simple)
```bash
export ARM_ACCESS_KEY="your-storage-account-key"
terraform init
```

### Option 2: Service Principal (Recommended for CI/CD)
```bash
export ARM_CLIENT_ID="your-client-id"
export ARM_CLIENT_SECRET="your-client-secret"
export ARM_SUBSCRIPTION_ID="your-subscription-id"
export ARM_TENANT_ID="your-tenant-id"
terraform init
```

### Option 3: Managed Identity (For Azure-hosted resources)
```bash
export ARM_USE_MSI=true
export ARM_SUBSCRIPTION_ID="your-subscription-id"
terraform init
```

## Security Best Practices

1. **Access Control**: Use Azure RBAC to control who can access the storage account
2. **Network Security**: Consider enabling firewall rules or private endpoints
3. **Key Rotation**: Regularly rotate storage account keys
4. **Monitoring**: Enable logging and monitoring for the storage account
5. **State Locking**: Terraform automatically handles state locking with Azure backend

## Troubleshooting

### Storage Account Name Already Exists
Storage account names must be globally unique. The script generates a unique name using timestamp/random numbers.

### Permission Errors
Ensure you have the following permissions:
- Contributor or Owner role on the subscription/resource group
- Storage Account Contributor role

### Terraform Init Fails
1. Verify the backend configuration matches your storage account details
2. Check that ARM_ACCESS_KEY is set correctly
3. Ensure the storage account and container exist

## Multiple Environments

For multiple environments (dev, staging, prod), you can:

1. Use different keys in the same container:
   ```hcl
   key = "dev/terraform.tfstate"
   key = "staging/terraform.tfstate"
   key = "prod/terraform.tfstate"
   ```

2. Use workspace-specific keys:
   ```hcl
   key = "${terraform.workspace}/terraform.tfstate"
   ```

3. Create separate storage accounts per environment (more secure)

## Cost Considerations

- Standard_LRS is the most cost-effective option for Terraform state files
- Hot access tier is recommended for frequently accessed state files
- Monitor storage costs in Azure Cost Management
