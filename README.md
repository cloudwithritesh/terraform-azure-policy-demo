# Terraform Azure Policy Implementation Runbook

This comprehensive guide walks you through implementing Azure Policy using Terraform, first with local development and then transitioning to GitHub Actions with OIDC authentication for secure, secret-free deployments.

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Project Structure](#project-structure)
4. [Local Development Setup](#local-development-setup)
5. [Understanding Terraform Configuration](#understanding-terraform-configuration)
6. [Understanding Azure Policy](#understanding-azure-policy)
7. [GitHub OIDC Setup](#github-oidc-setup)
8. [GitHub Actions Setup](#github-actions-setup)
9. [Testing the Policy](#testing-the-policy)
10. [Troubleshooting](#troubleshooting)

## Overview

This project demonstrates how to implement and enforce Azure Policies using Infrastructure as Code (IaC) principles with Terraform. The specific policy enforces the presence of an "Environment" tag on all Azure resources created within a resource group.

Key components:
- Terraform for infrastructure provisioning
- Azure Policy for governance and compliance
- GitHub Actions for CI/CD (optional)
- OpenID Connect (OIDC) for secure authentication without secrets (optional)

## Prerequisites

- An Azure subscription
- Azure CLI installed locally
- Terraform v1.6+ installed locally
- Git for version control
- Proper Azure permissions to:
  - Create service principals
  - Assign roles
  - Create storage accounts
  - Define and assign policies

## Project Structure

```plain
terraform-azure-policy-demo/
├── policy/
│   └── require-tags-policy.json      # Azure Policy definition
│   └── allowed-regions-policy.json   # Azure Policy definition
├── .gitignore                        # Git ignore file
├── main.tf                           # Main Terraform configuration
├── outputs.tf                        # Terraform outputs
├── providers.tf                      # Provider configuration
├── README.md                         # Project overview
├── terraform.tfvars                  # Variable values
└── variables.tf                      # Variable declarations
```

## Local Development Setup

### 1. Set Up Azure Storage for Terraform State

```bash
# Login to Azure
az login

# Set subscription ID
az account set --subscription <SUBSCRIPTION_ID>

# Create resource group
az group create --name tfstate-rg --location southeastasia

# Create storage account
az storage account create --name tfstate<UNIQUE_SUFFIX> --resource-group tfstate-rg --sku Standard_LRS --encryption-services blob

# Get storage account key
$ACCOUNT_KEY=$(az storage account keys list --resource-group tfstate-rg --account-name tfstate<UNIQUE_SUFFIX> --query '[0].value' -o tsv)
```
  *run **$ACCOUNT_KEY** in terminal to confirm the key value output*
```bash
# Create blob container
az storage container create --name tfstate --account-name tfstate<UNIQUE_SUFFIX> --account-key $ACCOUNT_KEY
```

### 2. Create Service Principal for Terraform

```bash
# Create service principal and save output
az ad sp create-for-rbac --name terraform-policy-demo --role Contributor --scopes /subscriptions/<SUBSCRIPTION_ID> --output json
```
  *copy the json Output from above to your favorite notepad or text editor and save it, we will need the key value <APP_ID> in next step*

```bash
# Add Storage Blob Data Contributor role for state management
az role assignment create --assignee <APP_ID> --role "Storage Blob Data Contributor" --scope /subscriptions/<SUBSCRIPTION_ID>/resourceGroups/tfstate-rg/providers/Microsoft.Storage/storageAccounts/tfstate<UNIQUE_SUFFIX>
```

### 3. Set Environment Variables

```bash
# Use credentials from sp-credentials.json
  ## if using bash the set env as 'export'; if using cmd or powershell instead use '$' e.g. $ARM_CLIENT_ID
export ARM_CLIENT_ID="<service_principal_app_id>"
export ARM_CLIENT_SECRET="<service_principal_password>"
export ARM_TENANT_ID="<tenant_id>"
export ARM_SUBSCRIPTION_ID="<subscription_id>"
```

### 4. Configure Terraform Backend

Update providers.tf:

```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "tfstate<UNIQUE_SUFFIX>"               # Storage account created in step 1
    container_name      = "tfstate"                               # Blob container created in step 1
    key                 = "terraform.tfstate"                     # This blob file will be created by terraform, once terraform init is run.
  }
}

provider "azurerm" {
  features {}
}
```

### 5. Initialize Terraform directory

```bash
# run below in terminal to initialize terraform directory
terraform init

# Initializing the backend...

# Successfully configured the backend "azurerm"! Terraform will automatically
# use this backend unless the backend configuration changes.
# Initializing provider plugins...
# - Finding hashicorp/azuread versions matching "~> 2.47.0"...
# - Finding latest version of hashicorp/azurerm...
# - Installing hashicorp/azuread v2.47.0...
# - Installed hashicorp/azuread v2.47.0 (signed by HashiCorp)
# - Installing hashicorp/azurerm v4.26.0...
# - Installed hashicorp/azurerm v4.26.0 (signed by HashiCorp)
# Terraform has created a lock file .terraform.lock.hcl to record the provider  
# selections it made above. Include this file in your version control repository
# so that Terraform can guarantee to make the same selections by default when   
# you run "terraform init" in the future.

# Terraform has been successfully initialized!

# You may now begin working with Terraform. Try running "terraform plan" to see
# any changes that are required for your infrastructure. All Terraform commands
# should now work.
```

## Understanding Terraform Configuration

### variables.tf

```hcl
variable "location" {
  type    = string
  default = "Southeast Asia"
}
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
    storage_account_name = "hugdemotfstate2304"
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

## Understanding Azure Policy

### Azure Policy JSON Structure (require-tags-policy.json)

```json
{
  "if": {
    "field": "[concat('tags[', 'Environment', ']')]",
    "exists": "false"
  },
  "then": {
    "effect": "deny"
  }
}
```

This policy:
- Evaluates all resources (`mode: "All"`)
- Checks if the "Environment" tag exists
- Denies creation/update if the tag is missing

### Create Azure policy assignment by running Terraform command

```bash
terraform plan    #This command will show the changes that will be performed by terraform apply command

## output ommited for brevity
data.azurerm_subscription.current: Reading...
data.azurerm_subscription.current: Read complete after 0s [id=/subscriptions/0000000-000-000-000-0000000]

Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # azurerm_policy_definition.require_env_tag will be created
  + resource "azurerm_policy_definition" "require_env_tag" {
      + description         = "Enforces the existence of an 'Environment' tag on all resources."
        }

  # azurerm_resource_group.demo_rg will be created
  + resource "azurerm_resource_group" "demo_rg" {
      + id       = (known after apply)
    }

  # azurerm_resource_group_policy_assignment.require_env_tag_assignment will be created
  + resource "azurerm_resource_group_policy_assignment" "require_env_tag_assignment" {
      + description          = "Assignment of require-env-tag policy"
      + display_name         = "Require Environment Tag Assignment"
      + enforce              = true
      + id                   = (known after apply)
      + metadata             = (known after apply)
      + name                 = "require-env-tag-assignment"
      + policy_definition_id = (known after apply)
      + resource_group_id    = (known after apply)
    }

Plan: 3 to add, 0 to change, 0 to destroy.

────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────── 

Note: You didn't use the -out option to save this plan, so Terraform can't guarantee to take exactly these actions if you run "terraform apply" now.
```

*If you hit below error, do not worry, there is a simple solution*
```error
Error: Error acquiring the state lock
│ Error message: state blob is already locked
```
**Solution**: *Go to Azure storage account created for state file --> on the '**terraform.tfstate**' file click on '**...**' on the right corner and break the lease*

### If your Plan output is what you expected, then run below command

```bash
terraform apply   # you can add '-auto-approve' option if you want to run without intervention

# output ommited for brevity
data.azurerm_subscription.current: Reading...
data.azurerm_subscription.current: Read complete after 0s [id=/subscriptions/000000-000-0000-00000]

Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # azurerm_policy_definition.require_env_tag will be created
  + resource "azurerm_policy_definition" "require_env_tag" {
    }

  # azurerm_resource_group.demo_rg will be created
  + resource "azurerm_resource_group" "demo_rg" {
    }

  # azurerm_resource_group_policy_assignment.require_env_tag_assignment will be created
  + resource "azurerm_resource_group_policy_assignment" "require_env_tag_assignment" {
    }

Plan: 3 to add, 0 to change, 0 to destroy.
azurerm_resource_group.demo_rg: Creating...
azurerm_policy_definition.require_env_tag: Creating...
azurerm_policy_definition.require_env_tag: Still creating... [00m10s elapsed]
azurerm_resource_group.demo_rg: Still creating... [00m10s elapsed]
azurerm_resource_group.demo_rg: Creation complete after 10s [id=/subscriptions/00000000-0000-0000-0000-0000000/resourceGroups/rg-policy-demo]
azurerm_policy_definition.require_env_tag: Still creating... [00m20s elapsed]
azurerm_policy_definition.require_env_tag: Still creating... [00m30s elapsed]
azurerm_policy_definition.require_env_tag: Creation complete after 1m33s [id=/subscriptions/0000000-000-0000-0000000/providers/Microsoft.Authorization/policyDefinitions/require-env-tag]
azurerm_resource_group_policy_assignment.require_env_tag_assignment: Creating...
azurerm_resource_group_policy_assignment.require_env_tag_assignment: Still creating... [00m10s elapsed]
azurerm_resource_group_policy_assignment.require_env_tag_assignment: Still creating... [00m20s elapsed]
azurerm_resource_group_policy_assignment.require_env_tag_assignment: Creation complete after 1m41s [id=/subscriptions/0000000-000-0000-0000000/resourceGroups/rg-policy-demo/providers/Microsoft.Authorization/policyAssignments/require-env-tag-assignment]

Apply complete! Resources: 3 added, 0 changed, 0 destroyed.
```

*'**We have Successfully Created Azure Policy using terraform with local dev workflow**'*

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

## Implement Azure policy using terraform + GitHub Actions + OIDC

In this implementation, we will update the Azure Policy assignment at the *Subscription* level. To allow resource creation only in *'**Southeast Asia**'* region

We will use the same Storage account for *'**State Management**'*.

*'**Follow below Steps**'*

## GitHub OIDC Setup

After successfully deploying your infrastructure locally, you can optionally set up GitHub Actions with OIDC for automated deployments.

### 1. Create Azure AD App Registration for OIDC

```bash
# Create the app registration
az ad app create --display-name "github-oidc-policy-demo"

# Get the application ID and object ID
az ad app list --display-name "github-oidc-policy-demo" --query "[].{displayName:displayName, objectId:id, appId:appId}" --output table

# Create service principal
az ad sp create --id <app_id>

# Add required role assignments
az role assignment create --assignee-object-id <object_id_of_service_principal> --assignee-principal-type ServicePrincipal --role Contributor --scope /subscriptions/<SUBSCRIPTION_ID>
az role assignment create --assignee-object-id <object_id_of_service_principal> --assignee-principal-type ServicePrincipal --role "Storage Blob Data Contributor" --scope /subscriptions/<SUBSCRIPTION_ID>/resourceGroups/tfstate-rg/providers/Microsoft.Storage/storageAccounts/tfstate<UNIQUE_SUFFIX>
```

```bash
# This role assignement is necassary for the OIDC to run terraform apply command when we merge the pull request
az role assignment create --assignee-object-id <object_id_of_service_principal> --assignee-principal-type ServicePrincipal --role "Resource Policy Contributor" --scope subscriptions/<SUSBSCRIPTION_ID>
```

### 2. Configure Federated Credentials

```bash
az ad app federated-credential create --id <object_id_of_AD_APP> --parameters '{
  "name": "github-oidc",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:YOUR_GITHUB_ORG/YOUR_REPO:ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"]
}'
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
# name: 'Terraform Azure Policy CI/CD'

# on:
#   push:
#     branches: [ main ]
#   pull_request:
#     branches: [ main ]
#   workflow_dispatch:

# permissions:
#   id-token: write
#   contents: read

# jobs:
#   terraform:
#     name: 'Terraform'
#     runs-on: ubuntu-latest
    
#     env:
#       ARM_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
#       ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
#       ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
#       ARM_USE_OIDC: true
    
#     # Use the Bash shell regardless whether the GitHub Actions runner is ubuntu-latest, macos-latest, or windows-latest
#     defaults:
#       run:
#         shell: bash

#     steps:
#     # Checkout the repository to the GitHub Actions runner
#     - name: Checkout
#       uses: actions/checkout@v3

#     # Install the latest version of Terraform CLI
#     - name: Setup Terraform
#       uses: hashicorp/setup-terraform@v2
#       with:
#         terraform_version: 1.6.0

#     # Initialize a new or existing Terraform working directory
#     - name: Terraform Init
#       run: terraform init

#     # Checks that all Terraform configuration files adhere to a canonical format
#     - name: Terraform Format
#       run: terraform fmt -check

#     # Validate terraform configuration
#     - name: Terraform Validate
#       run: terraform validate

#     # Generates an execution plan for Terraform
#     - name: Terraform Plan
#       if: github.event_name == 'pull_request'
#       run: terraform plan -no-color
#       continue-on-error: true

#     # Apply Terraform configuration if PR is merged or workflow is manually triggered
#     - name: Terraform Apply
#       if: github.ref == 'refs/heads/main' && (github.event_name == 'push' || github.event_name == 'workflow_dispatch')
#       run: terraform apply -auto-approve
```
**Currently *github-actions.yaml* workflow file is commented --> uncomment it --> ctrl+A -- ctrl+/ -- This will uncomment entire file.**

This workflow:
- Runs on pushes to main, pull requests, or manual triggers
- Uses OIDC for secure authentication
- Performs Terraform init, format check, validation, plan, and apply operations

## Update terraform config

Go to *'**az-policy.tf**'* file and uncomment **line 28-66**

Go to *'**providers.tf**'* file and do the following changes
```code
# Comment # subscription_id = var.subscription_id  AND
# Uncomment use_oidc = true
```

## Open GitHub Pull-Request & Merge it
```git
git checkout -b <new-branch-name>
git add .
git commit -m "Your Commit message"
git push origin <new-branch-name>"
```
This will create a new *Pull-Request* --> *github-actions.yaml* file will trigger the workflow --> In your GitHub Repository got to **Actions** Tab and check the *terraform* job.

Once, the *terraform* job is successfull --> Merge the PR to Main Branch --> In your GitHub Repository got to **Actions** Tab and check the *terraform* job. Once the job is successful you will see that the new Policy is applied.

## Testing the Policy

### Verify Policy Implementation

1. Navigate to the Azure Portal
2. Go to "Policy" service
3. Under "Assignments", find your policy assignment
4. Verify it appears with the name "Require Environment Tag Assignment"

### Test Policy Enforcement

1. Try to create a resource in the `rg-policy-demo` resource group without an "Environment" tag
   ```bash
   az group create --name my-terraform-rg --location eastus
   ```
   This should fail with a policy violation.

2. Create a resource with the required tag
   ```bash
   az group create --name my-terraform-rg --location southeastasia
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