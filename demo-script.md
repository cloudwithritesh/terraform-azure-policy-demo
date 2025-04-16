# 🧪 Demo Script – Terraform + Azure Policy + GitHub OIDC Login

This demo shows how to securely deploy an Azure Policy using **Terraform**, **GitHub Actions**, and **OIDC**—no secrets required.

---

## 📝 1. Prerequisites

- Azure CLI logged in (`az login`)
- Terraform v1.6+ installed
- GitHub repo created (e.g., `terraform-azure-policy-demo`)
- Permissions to create Azure resources and assign roles

---

## 🔐 2. Create Azure AD App Registration

```bash
az ad app create --display-name "terraform-oidc-app"
```

Note the **appId** and **objectId** for later use

## 🔑 3. Add Federated Credential for GitHub OIDC

```bash
az ad app federated-credential create --id <objectId> --parameters '{
  "name": "github-oidc",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:<GITHUB_ORG>/<REPO>:ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"]
}'
```

Replace `<GITHUB_ORG>` and `<REPO>` with your GitHub org/user and repo name.

## 🛡️ 4. Assign Required Azure Roles

```bash
# Contributor for managing resources
az role assignment create --assignee <appId> \
  --role Contributor \
  --scope /subscriptions/<SUBSCRIPTION_ID>

# Storage Blob Data Contributor for Terraform state
az role assignment create --assignee <appId> \
  --role "Storage Blob Data Contributor" \
  --scope /subscriptions/<SUBSCRIPTION_ID>/resourceGroups/tfstate-rg/providers/Microsoft.Storage/storageAccounts/tfstatestorage1234
```

## 💾 5. Set Up Azure Storage Backend for Terraform

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

## 🔧 6. Configure GitHub Secrets

Go to your GitHub repository:
Settings > Secrets and Variables > Actions > New Repository Secret

Add the following:

| **Name** | **Value** |
|----------|-----------|
| AZURE_CLIENT_ID | From App Registration |
| AZURE_TENANT_ID | From Azure AD |
| AZURE_SUBSCRIPTION_ID | Your Azure Subscription ID |

## 📁 7. Project Structure Overview

```plain
terraform-azure-policy-demo/
├── .github/workflows/deploy.yml      # CI/CD pipeline
├── backend.tf                        # Remote state backend config
├── main.tf                           # Azure Policy + Assignment
├── policy/require-tags-policy.json   # Tag enforcement policy
├── variables.tf                      # Input variables
├── terraform.tfvars                  # Optional local values
├── outputs.tf                        # Output values
└── demo-script.md                    # This file
```

## 🧪 8. Run Locally (Optional for Dev)

Create a service principal for local dev:

```bash
az ad sp create-for-rbac --name terraform-local --role Contributor \
  --scopes /subscriptions/<SUBSCRIPTION_ID> --sdk-auth
```

Export credentials:

```bash
export ARM_CLIENT_ID=""
export ARM_CLIENT_SECRET=""
export ARM_TENANT_ID=""
export ARM_SUBSCRIPTION_ID=""
```

Then run:

```bash
terraform init
terraform plan
terraform apply -auto-approve
```

## 🚀 9. Trigger GitHub Actions CI/CD

Make a commit and push to the main branch:

```bash
git add .
git commit -m "trigger deploy"
git push origin main
```

Watch the Actions tab for deployment logs.