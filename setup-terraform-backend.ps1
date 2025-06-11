# PowerShell Script to create Azure Storage Account for Terraform Backend
# This script creates the necessary Azure resources to store Terraform state files remotely

param(
    [string]$ResourceGroupName = "rg-terraform-state",
    [string]$StorageAccountName = "sttfstate$((Get-Date).ToString('yyyyMMddHHmmss'))",
    [string]$ContainerName = "tfstate",
    [string]$Location = "East US",
    [string]$SubscriptionId = ""
)

# Function to write colored output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Write-Info {
    param([string]$Message)
    Write-ColorOutput "[INFO] $Message" "Green"
}

function Write-Warning {
    param([string]$Message)
    Write-ColorOutput "[WARNING] $Message" "Yellow"
}

function Write-Error {
    param([string]$Message)
    Write-ColorOutput "[ERROR] $Message" "Red"
}

# Check if Azure CLI is installed
function Test-AzureCLI {
    try {
        az --version | Out-Null
        return $true
    }
    catch {
        Write-Error "Azure CLI is not installed. Please install it first:"
        Write-Host "  Install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        return $false
    }
}

# Check if user is logged in to Azure
function Test-AzureLogin {
    try {
        az account show | Out-Null
        return $true
    }
    catch {
        Write-Error "You are not logged in to Azure. Please run: az login"
        return $false
    }
}

# Set subscription if provided
function Set-AzureSubscription {
    if ($SubscriptionId) {
        Write-Info "Setting subscription to: $SubscriptionId"
        az account set --subscription $SubscriptionId
    }
    else {
        $currentSub = az account show --query name --output tsv
        Write-Info "Using current subscription: $currentSub"
    }
}

# Create resource group
function New-ResourceGroup {
    Write-Info "Creating resource group: $ResourceGroupName"
    
    $rgExists = az group show --name $ResourceGroupName 2>$null
    if ($rgExists) {
        Write-Warning "Resource group $ResourceGroupName already exists"
    }
    else {
        az group create `
            --name $ResourceGroupName `
            --location $Location `
            --tags purpose="terraform-backend" environment="shared"
        
        Write-Info "Resource group created successfully"
    }
}

# Create storage account
function New-StorageAccount {
    Write-Info "Creating storage account: $StorageAccountName"
    
    # Check if storage account name is available
    $nameAvailable = az storage account check-name --name $StorageAccountName --query nameAvailable --output tsv
    if ($nameAvailable -ne "true") {
        Write-Error "Storage account name $StorageAccountName is not available"
        $StorageAccountName = "sttfstate$((Get-Random -Maximum 9999))"
        Write-Info "Using alternative name: $StorageAccountName"
    }
    
    az storage account create `
        --name $StorageAccountName `
        --resource-group $ResourceGroupName `
        --location $Location `
        --sku Standard_LRS `
        --kind StorageV2 `
        --access-tier Hot `
        --https-only true `
        --min-tls-version TLS1_2 `
        --allow-blob-public-access false `
        --tags purpose="terraform-backend" environment="shared"
    
    Write-Info "Storage account created successfully"
    return $StorageAccountName
}

# Create blob container
function New-BlobContainer {
    param([string]$AccountName)
    
    Write-Info "Creating blob container: $ContainerName"
    
    # Get storage account key
    $storageKey = az storage account keys list `
        --resource-group $ResourceGroupName `
        --account-name $AccountName `
        --query '[0].value' `
        --output tsv
    
    # Create container
    az storage container create `
        --name $ContainerName `
        --account-name $AccountName `
        --account-key $storageKey `
        --public-access off
    
    Write-Info "Blob container created successfully"
    return $storageKey
}

# Configure storage account security
function Set-StorageSecurity {
    param([string]$AccountName)
    
    Write-Info "Configuring storage account security settings"
    
    # Enable versioning
    az storage account blob-service-properties update `
        --resource-group $ResourceGroupName `
        --account-name $AccountName `
        --enable-versioning true
    
    # Enable soft delete for blobs
    az storage account blob-service-properties update `
        --resource-group $ResourceGroupName `
        --account-name $AccountName `
        --enable-delete-retention true `
        --delete-retention-days 30
    
    Write-Info "Security settings configured"
}

# Output Terraform configuration
function Write-TerraformConfig {
    param(
        [string]$AccountName,
        [string]$StorageKey
    )
    
    Write-Info "Terraform backend configuration:"
    Write-Host ""
    Write-Host "Add this to your Terraform configuration:"
    Write-Host ""
    
    $config = @"
terraform {
  backend "azurerm" {
    resource_group_name  = "$ResourceGroupName"
    storage_account_name = "$AccountName"
    container_name       = "$ContainerName"
    key                  = "terraform.tfstate"
  }
}
"@
    
    Write-Host $config
    Write-Host ""
    
    Write-Info "Storage Account Details:"
    Write-Host "  Resource Group: $ResourceGroupName"
    Write-Host "  Storage Account: $AccountName"
    Write-Host "  Container: $ContainerName"
    Write-Host "  Location: $Location"
    Write-Host ""
    
    Write-Info "Environment variables for Terraform authentication:"
    Write-Host "  `$env:ARM_ACCESS_KEY = `"$StorageKey`""
    Write-Host ""
    
    Write-Warning "Store the ARM_ACCESS_KEY securely. You'll need it for Terraform operations."
}

# Main execution
function Main {
    Write-Info "Starting Azure Storage Account setup for Terraform backend"
    Write-Host ""
    
    # Perform checks
    if (-not (Test-AzureCLI)) { exit 1 }
    if (-not (Test-AzureLogin)) { exit 1 }
    
    Set-AzureSubscription
    
    # Create resources
    New-ResourceGroup
    $accountName = New-StorageAccount
    $storageKey = New-BlobContainer -AccountName $accountName
    Set-StorageSecurity -AccountName $accountName
    
    # Output configuration
    Write-TerraformConfig -AccountName $accountName -StorageKey $storageKey
    
    Write-Info "Setup completed successfully!"
    Write-Host ""
    Write-Info "Next steps:"
    Write-Host "1. Add the backend configuration to your Terraform files"
    Write-Host "2. Run 'terraform init' to initialize the backend"
    Write-Host "3. Set the ARM_ACCESS_KEY environment variable"
    Write-Host ""
    
    Write-Info "Azure Portal link:"
    $subscriptionId = az account show --query id --output tsv
    $portalUrl = "https://portal.azure.com/#@/resource/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Storage/storageAccounts/$accountName"
    Write-Host $portalUrl
}

# Run main function
Main
