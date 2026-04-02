#!/bin/bash
# =============================================================================
# Setup OIDC Federation between GitHub Actions and Azure
# =============================================================================
# This creates a Service Principal with federated credentials so GitHub Actions
# can authenticate to Azure WITHOUT storing client secrets.
#
# Prerequisites: Azure CLI logged in as Owner/User Access Admin
# Usage: ./setup-oidc.sh <github_org> <github_repo> <subscription_id>
# =============================================================================

set -euo pipefail

GITHUB_ORG="${1:?Usage: $0 <github_org> <github_repo> <subscription_id>}"
GITHUB_REPO="${2:?GitHub repo name required}"
SUBSCRIPTION_ID="${3:?Subscription ID required}"
APP_NAME="sp-terraform-${GITHUB_ORG}-${GITHUB_REPO}"

echo "============================================="
echo " OIDC Setup: GitHub → Azure"
echo "============================================="
echo " GitHub:       ${GITHUB_ORG}/${GITHUB_REPO}"
echo " Subscription: ${SUBSCRIPTION_ID}"
echo " App Name:     ${APP_NAME}"
echo "============================================="

# Create App Registration
echo ">>> Creating App Registration..."
APP_ID=$(az ad app create --display-name "${APP_NAME}" --query appId -o tsv)
echo "    App ID: ${APP_ID}"

# Create Service Principal
echo ">>> Creating Service Principal..."
SP_OBJECT_ID=$(az ad sp create --id "${APP_ID}" --query id -o tsv)
echo "    SP Object ID: ${SP_OBJECT_ID}"

# Assign Contributor role at subscription level
echo ">>> Assigning Contributor role at subscription scope..."
az role assignment create \
  --assignee "${SP_OBJECT_ID}" \
  --role "Contributor" \
  --scope "/subscriptions/${SUBSCRIPTION_ID}"

# Add federated credential for main branch
echo ">>> Adding federated credential (main branch)..."
az ad app federated-credential create \
  --id "${APP_ID}" \
  --parameters "{
    \"name\": \"github-main\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:${GITHUB_ORG}/${GITHUB_REPO}:ref:refs/heads/main\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }"

# Add federated credential for pull requests
echo ">>> Adding federated credential (pull requests)..."
az ad app federated-credential create \
  --id "${APP_ID}" \
  --parameters "{
    \"name\": \"github-pr\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:${GITHUB_ORG}/${GITHUB_REPO}:pull_request\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }"

# Add federated credential for environments (dev, staging, prod)
for ENV in dev staging prod; do
  echo ">>> Adding federated credential (environment: ${ENV})..."
  az ad app federated-credential create \
    --id "${APP_ID}" \
    --parameters "{
      \"name\": \"github-env-${ENV}\",
      \"issuer\": \"https://token.actions.githubusercontent.com\",
      \"subject\": \"repo:${GITHUB_ORG}/${GITHUB_REPO}:environment:${ENV}\",
      \"audiences\": [\"api://AzureADTokenExchange\"]
    }"
done

TENANT_ID=$(az account show --query tenantId -o tsv)

echo ""
echo "============================================="
echo " OIDC Setup Complete!"
echo "============================================="
echo ""
echo "Add these as GitHub repository secrets:"
echo "  ARM_CLIENT_ID:       ${APP_ID}"
echo "  ARM_TENANT_ID:       ${TENANT_ID}"
echo "  ARM_SUBSCRIPTION_ID: ${SUBSCRIPTION_ID}"
echo ""
echo "No ARM_CLIENT_SECRET needed — OIDC handles authentication!"
