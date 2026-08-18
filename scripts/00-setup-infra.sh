#!/usr/bin/env bash
# 00 - Create the lab infrastructure: a resource group and a storage account
# with one blob container. This is the "target" the app will access via RBAC.
set -euo pipefail
source "$(dirname "$0")/../.env"

echo "==> Creating resource group $LAB_RG in $LAB_LOCATION..."
az group create --name "$LAB_RG" --location "$LAB_LOCATION" --output none

echo "==> Creating storage account $LAB_STORAGE..."
az storage account create \
  --name "$LAB_STORAGE" \
  --resource-group "$LAB_RG" \
  --location "$LAB_LOCATION" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  --output none

echo "==> Creating a test container (using your own identity)..."
az storage container create \
  --name "lab-data" \
  --account-name "$LAB_STORAGE" \
  --auth-mode login \
  --output none

# Persist state for the next scripts
STATE="$(dirname "$0")/../.lab-state"
{
  echo "LAB_STORAGE_ACTUAL=$LAB_STORAGE"
} > "$STATE"

echo "==> Done. Storage account: $LAB_STORAGE (saved to .lab-state)"
