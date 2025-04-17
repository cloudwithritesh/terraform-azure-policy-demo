# Terraform Azure Policy Implementation Runbook

This comprehensive guide walks you through implementing Azure Policy using Terraform and GitHub Actions with OIDC authentication for secure, secret-free deployments.

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Project Structure](#project-structure)
4. [Setting Up Azure Resources](#setting-up-azure-resources)
5. [GitHub Actions Setup](#github-actions-setup)
6. [Understanding Terraform Configuration](#understanding-terraform-configuration)
7. [Understanding Azure Policy](#understanding-azure-policy)
8. [Local Development Workflow](#local-development-workflow)
9. [CI/CD Workflow](#cicd-workflow)
10. [Testing the Policy](#testing-the-policy)
11. [Troubleshooting](#troubleshooting)

## Overview

This project demonstrates how to implement and enforce Azure Policies using Infrastructure as Code (IaC) principles with Terraform. The specific policy enforces the presence of an "Environment" tag on all Azure resources created within a resource group.

Key components:
- Terraform for infrastructure provisioning
- Azure Policy for governance and compliance
- GitHub Actions for CI/CD
- OpenID Connect (OIDC) for secure authentication without secrets

## Prerequisites

- An Azure subscription
- GitHub account and repository
- Azure CLI installed locally (for initial setup)
- Terraform v1.6+ installed locally (for local development)
- Proper Azure permissions to:
  - Create Azure AD applications
  - Assign roles
  - Create storage accounts
  - Define and assign policies

## Project Structure

```plain
terraform-azure-policy-demo/
├── .github/
│   └── workflows/
│       └── github-actions.yaml       # CI/CD pipeline configuration
│
├── policy/
│   └── require-tags-policy.json      # Azure Policy definition
│
├── .gitignore                        # Git ignore file
├── demo-script.md                    # Demo walkthrough
├── github-oidc.tf                    # GitHub OIDC configuration
├── main.tf                           # Main Terraform configuration
├── outputs.tf                        # Terraform outputs
├── providers.tf                      # Provider configuration
├── README.md                         # Project overview
├── terraform.tfvars                  # Variable values
└── variables.tf                      # Variable declarations
```

## Setting Up Azure Resources

### 1. Create Azure AD App Registration

```bash
az ad app create --display-name "terraform-oidc-app"
```

Note the `appId` and `objectId` from the output.

### 2. Configure Federated Credentials for GitHub OIDC

```bash
az ad app federated-credential create --id <objectId> --parameters '{
  "name": "github-oidc",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:<GITHUB_ORG>/<REPO>:ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"]
}'
```

Replace `<GITHUB_ORG>` and `<REPO>` with your GitHub organization/username and repository name.

### 3. Assign Required Azure Roles

```bash
# Assign Contributor role at subscription level
az role assignment create --assignee <appId> \
  --role Contributor \
  --scope /subscriptions/<SUBSCRIPTION_ID>

# Assign Storage Blob Data Contributor role for Terraform state management
az role assignment create --assignee <appId> \
  --role "Storage Blob Data Contributor" \
  --scope /subscriptions/<SUBSCRIPTION_ID>/resourceGroups/tfstate-rg/providers/Microsoft.Storage/storageAccounts/tfstatestorage1234
```

### 4. Set Up Azure Storage for Terraform State

```bash
# Create resource group
az group create --name tfstate-rg --location eastus

# Create storage account
az storage account create --name tfstatestorage1234 \
  --resource-group tfstate-rg \
  --sku Standard_LRS \
  --encryption-services blob

# Get storage account key
ACCOUNT_KEY=$(az storage account keys list \
  --resource-group tfstate-rg \
  --account-name tfstatestorage1234 \
  --query '[0].value' -o tsv)

# Create blob container for Terraform state
az storage container create \
  --name tfstate \
  --account-name tfstatestorage1234 \
  --account-key $ACCOUNT_KEY
```

## GitHub Actions Setup

### 1. Configure GitHub Repository Secrets

Navigate to your GitHub repository:
Settings > Secrets and Variables > Actions > New Repository Secret

Add the following secrets:

| **Name** | **Value** | **Description** |
|----------|-----------|-----------------|
| AZURE_CLIENT_ID | `<appId>` | The App Registration client ID |
| AZURE_TENANT_ID | `<tenantId>` | Your Azure AD tenant ID |
| AZURE_SUBSCRIPTION_ID | `<subscriptionId>` | Your Azure subscription ID |

### 2. GitHub Actions Workflow

The workflow is defined in `.github/workflows/github-actions.yaml`:

```yaml
name: 'Terraform Azure Policy CI/CD'

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]
  workflow_dispatch:

permissions:
  id-token: write
  contents: read

jobs:
  terraform:
    name: 'Terraform'
    runs-on: ubuntu-latest
    
    env:
      ARM_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
      ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
      ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      ARM_USE_OIDC: true
    
    defaults:
      run:
        shell: bash

    steps:
    - name: Checkout
      uses: actions/checkout@v3

    - name: Setup Terraform
      uses: hashicorp/setup-terraform@v2
      with:
        terraform_version: 1.6.0

    - name: Terraform Init
      run: terraform init

    - name: Terraform Format
      run: terraform fmt -check

    - name: Terraform Validate
      run: terraform validate

    - name: Terraform Plan
      if: github.event_name == 'pull_request'
      run: terraform plan -no-color
      continue-on-error: true

    - name: Terraform Apply
      if: github.ref == 'refs/heads/main' && (github.event_name == 'push' || github.event_name == 'workflow_dispatch')
      run: terraform apply -auto-approve
```

This workflow:
- Runs on pushes to main, pull requests, or manual triggers
- Uses OIDC for secure authentication
- Performs Terraform init, format check, validation, plan, and apply operations

## Understanding Terraform Configuration

### variables.tf

```hcl
variable "location" {
  type    = string
  default = "East US"
}
```

### terraform.tfvars

```hcl
location = "Southeast Asia"
```

### providers.tf

```hcl
terraform {
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.47.0"
    }
  }
  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "tfstatestorage1234"
    container_name       = "tfstate"
    key                  = "azure-policy-demo.terraform.tfstate"
  }
}

provider "azuread" {}

provider "azurerm" {
  features {}
}
```

### main.tf

```hcl
resource "azurerm_resource_group" "demo_rg" {
  name     = "rg-policy-demo"
  location = var.location
}

resource "azurerm_policy_definition" "require_env_tag" {
  name         = "require-env-tag"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "Require Environment Tag"
  description  = "Enforces the existence of an 'Environment' tag on all resources."

  policy_rule = file("${path.module}/policy/require-tags-policy.json")
}

resource "azurerm_policy_assignment" "require_env_tag_assignment" {
  name                 = "require-env-tag-assignment"
  policy_definition_id = azurerm_policy_definition.require_env_tag.id
  scope                = azurerm_resource_group.demo_rg.id
  description          = "Assignment of require-env-tag policy"
  display_name         = "Require Environment Tag Assignment"
}
```

### github-oidc.tf

This file configures the GitHub OIDC integration:

```hcl
data "azurerm_subscription" "current" {}

resource "azuread_application" "github_oidc_app" {
  display_name = "terraform-oidc-app"
}

resource "azuread_service_principal" "github_oidc_sp" {
  application_id = azuread_application.github_oidc_app.application_id
}

resource "azuread_application_federated_identity_credential" "github_oidc" {
  application_object_id = azuread_application.github_oidc_app.object_id
  display_name          = "github-oidc"
  description           = "OIDC login from GitHub Actions"
  audiences             = ["api://AzureADTokenExchange"]
  issuer                = "https://token.actions.githubusercontent.com"
  subject               = "repo:<GITHUB_ORG>/<REPO>:ref:refs/heads/main"
}

# Contributor Role Assignment at Subscription Scope
resource "azurerm_role_assignment" "contributor" {
  principal_id         = azuread_service_principal.github_oidc_sp.object_id
  role_definition_name = "Contributor"
  scope                = data.azurerm_subscription.current.id
}

# Storage Blob Data Contributor on the Terraform state storage account
data "azurerm_storage_account" "tfstate" {
  name                = "<STORAGE_ACCOUNT_NAME>"
  resource_group_name = "<STORAGE_ACCOUNT_RG>"
}

resource "azurerm_role_assignment" "storage_blob_contributor" {
  principal_id         = azuread_service_principal.github_oidc_sp.object_id
  role_definition_name = "Storage Blob Data Contributor"
  scope                = data.azurerm_storage_account.tfstate.id
}
```

**Important Note:** Replace placeholders in the `subject` and `data "azurerm_storage_account"` blocks with your actual values.

## Understanding Azure Policy

### Azure Policy JSON Structure (require-tags-policy.json)

```json
{
  "properties": {
    "displayName": "Require Environment Tag",
    "policyType": "Custom",
    "mode": "All",
    "description": "This policy ensures that the 'Environment' tag is present on all resources.",
    "parameters": {},
    "policyRule": {
      "if": {
        "field": "[concat('tags[', 'Environment', ']')]",
        "exists": "false"
      },
      "then": {
        "effect": "deny"
      }
    }
  }
}
```

This policy:
- Evaluates all resources (`mode: "All"`)
- Checks if the "Environment" tag exists
- Denies creation/update if the tag is missing

## Local Development Workflow

### 1. Create Service Principal for Local Development

```bash
az ad sp create-for-rbac --name terraform-local --role Contributor \
  --scopes /subscriptions/<SUBSCRIPTION_ID> --sdk-auth
```

### 2. Set Environment Variables

```bash
export ARM_CLIENT_ID="<client_id>"
export ARM_CLIENT_SECRET="<client_secret>"
export ARM_TENANT_ID="<tenant_id>"
export ARM_SUBSCRIPTION_ID="<subscription_id>"
```

### 3. Initialize Terraform

```bash
terraform init
```

### 4. Plan Terraform Changes

```bash
terraform plan
```

### 5. Apply Terraform Configuration

```bash
terraform apply
```

## CI/CD Workflow

### Pull Request Workflow

1. Create a feature branch from main
2. Make changes to Terraform configuration
3. Create a pull request to main
4. GitHub Actions automatically runs:
   - `terraform init`
   - `terraform fmt -check`
   - `terraform validate`
   - `terraform plan`
5. Review the plan in the PR comments
6. Approve and merge the PR

### Merge/Push Workflow

1. When changes are merged to main:
   - GitHub Actions automatically runs all previous checks
   - `terraform apply -auto-approve` is executed
2. The infrastructure changes are applied in Azure

## Testing the Policy

### Verify Policy Implementation

1. Navigate to the Azure Portal
2. Go to "Policy" service
3. Under "Assignments", find your policy assignment
4. Verify it appears with the name "Require Environment Tag Assignment"

### Test Policy Enforcement

1. Try to create a resource in the `rg-policy-demo` resource group without an "Environment" tag
   ```bash
   az storage account create \
     --name testpolicyaccount \
     --resource-group rg-policy-demo \
     --sku Standard_LRS
   ```
   This should fail with a policy violation.

2. Create a resource with the required tag
   ```bash
   az storage account create \
     --name testpolicyaccount \
     --resource-group rg-policy-demo \
     --sku Standard_LRS \
     --tags Environment=Dev
   ```
   This should succeed.

## Troubleshooting

### Common GitHub Actions Issues

1. **OIDC Authentication Failures**
   - Verify the federated credential is configured correctly
   - Check the GitHub repository name in the subject identifier
   - Ensure the app registration has the correct permissions

2. **Terraform State Access Issues**
   - Verify the role assignment for the storage account
   - Check storage account name and resource group
   - Ensure container exists

### Common Azure Policy Issues

1. **Policy Not Enforced**
   - It can take up to 30 minutes for policy assignments to take effect
   - Verify scope is set correctly
   - Check policy assignment properties

2. **Policy Definition Issues**
   - Validate JSON syntax
   - Check the policy effect (audit vs. deny)
   - Verify field references in the policy rule

### Getting Help

For more detailed assistance:
- Check Azure Policy documentation: https://docs.microsoft.com/en-us/azure/governance/policy/
- Review Terraform Registry for Azure providers: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs