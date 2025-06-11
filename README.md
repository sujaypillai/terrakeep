# Terrakeep - Azure Landing Zone with Terraform

## Project Purpose

This project demonstrates how to create an **Azure Landing Zone using Terraform** with proper state management and recommended project structure.

### Key Objectives

- **Azure Landing Zone Creation**: Provision a comprehensive Azure Landing Zone using Terraform infrastructure as code
- **Recommended Project Structure**: Implement best practices for organizing and managing Terraform code for Azure resource provisioning
- **Remote State Management**: Store Terraform state files remotely in Azure Blob Storage for safe, collaborative, and secure state management

### Features

- ✅ Azure Storage Account with private endpoint for secure Terraform state storage
- ✅ Blob container specifically configured for Terraform state files
- ✅ Authentication and access control setup
- 🚧 Comprehensive Terraform project structure (coming next)
- 🚧 Azure Landing Zone modules and configurations (coming next)

## Quick Start

### Prerequisites

Before using this project, ensure you have:

- Azure CLI installed and configured
- An active Azure subscription
- Appropriate permissions to create resource groups, storage accounts, and networking resources
- Terraform installed (for future use with the state backend)

### Authentication

Authenticate with Azure CLI:

```bash
az login
az account set --subscription "your-subscription-id"
```

### Creating the Terraform State Storage

Run the provided script to create the Azure Storage Account and container for Terraform state:

```bash
./scripts/create-terraform-backend.sh
```

This script will create:
- Resource group for the Terraform backend
- Storage account with private endpoint
- Blob container for state files
- Necessary network security configurations
