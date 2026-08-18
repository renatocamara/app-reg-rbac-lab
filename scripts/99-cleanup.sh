#!/usr/bin/env bash
# 99 - Tear down the lab infrastructure and local state.
set -euo pipefail
source "$(dirname "$0")/../.env"

echo "==> Removing lab custom role (if script 07 was run)..."
SUB_ID=$(az account show --query id -o tsv)
ROLE_NAME="${LAB_PREFIX}-subscription-canceller"
for A_ID in $(az role assignment list --role "$ROLE_NAME" --scope "/subscriptions/$SUB_ID" --query '[].id' -o tsv 2>/dev/null); do
  az role assignment delete --ids "$A_ID" 2>/dev/null || true
done
az role definition delete --name "$ROLE_NAME" 2>/dev/null || true

echo "==> Deleting resource group $LAB_RG (async)..."
az group delete --name "$LAB_RG" --yes --no-wait

echo "==> Removing local state file..."
rm -f "$(dirname "$0")/../.lab-state"

echo "==> Done. Resource group deletion runs in the background."
