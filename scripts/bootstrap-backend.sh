#!/bin/bash
# =============================================================================
# Bootstrap Azure Backend for Terraform State
# =============================================================================
# Run this ONCE per subscription to set up the state storage infrastructure.
# This creates:
#   - Resource Group
#   - Storage Account (with versioning, encryption, no public access)
#   - Blob Container for state files
#
# Prerequisites: Azure CLI logged in with sufficient permissions
# Usage: ./bootstrap-backend.sh <environment> <location> <subscription_id>
# =============================================================================

set -euo pipefail

ENV="${1:?Usage: $0 <environment> <location> <subscription_id>}"
LOCATION="${2:-eastus}"
SUBSCRIPTION_ID="${3:?Subscription ID required}"

# Naming convention
RESOURCE_GROUP="rg-terraform-state-${ENV}"
STORAGE_ACCOUNT="stterraformstate${ENV}"  # Must be globally unique, lowercase, no hyphens
CONTAINER_NAME="tfstate"

echo "============================================="
echo " Terraform State Backend Bootstrap"
echo "============================================="
echo " Environment:      ${ENV}"
echo " Location:         ${LOCATION}"
echo " Subscription:     ${SUBSCRIPTION_ID}"
echo " Resource Group:   ${RESOURCE_GROUP}"
echo " Storage Account:  ${STORAGE_ACCOUNT}"
echo " Container:        ${CONTAINER_NAME}"
echo "============================================="

# Set subscription
az account set --subscription "${SUBSCRIPTION_ID}"

# Create Resource Group
echo ">>> Creating Resource Group..."
az group create \
  --name "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --tags Purpose=TerraformState Environment="${ENV}" ManagedBy=PlatformEngineering

# Create Storage Account
echo ">>> Creating Storage Account..."
az storage account create \
  --name "${STORAGE_ACCOUNT}" \
  --resource-group "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  --https-only true \
  --tags Purpose=TerraformState Environment="${ENV}" ManagedBy=PlatformEngineering

# Enable versioning (state file recovery)
echo ">>> Enabling blob versioning..."
az storage account blob-service-properties update \
  --account-name "${STORAGE_ACCOUNT}" \
  --resource-group "${RESOURCE_GROUP}" \
  --enable-versioning true

# Enable soft delete for blobs (30 days retention)
echo ">>> Enabling soft delete..."
az storage account blob-service-properties update \
  --account-name "${STORAGE_ACCOUNT}" \
  --resource-group "${RESOURCE_GROUP}" \
  --delete-retention-days 30 \
  --enable-delete-retention true

# Create container
echo ">>> Creating blob container..."
az storage container create \
  --name "${CONTAINER_NAME}" \
  --account-name "${STORAGE_ACCOUNT}" \
  --auth-mode login

# Lock the resource group to prevent accidental deletion
echo ">>> Adding delete lock on Resource Group..."
az lock create \
  --name "DoNotDelete-TfState" \
  --resource-group "${RESOURCE_GROUP}" \
  --lock-type CanNotDelete \
  --notes "Protects Terraform state storage from accidental deletion"

echo ""
echo "============================================="
echo " Bootstrap Complete!"
echo "============================================="
echo ""
echo "Use these values in your workflow:"
echo "  backend_resource_group:  ${RESOURCE_GROUP}"
echo "  backend_storage_account: ${STORAGE_ACCOUNT}"
echo "  backend_container:       ${CONTAINER_NAME}"
echo ""
echo "Next steps:"
echo "  1. Create an Azure AD App Registration for OIDC"
echo "  2. Add federated credentials for your GitHub org/repo"
echo "  3. Set repository secrets: ARM_CLIENT_ID, ARM_TENANT_ID, ARM_SUBSCRIPTION_ID"
