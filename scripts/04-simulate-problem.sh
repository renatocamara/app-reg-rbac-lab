#!/usr/bin/env bash
# 04 - ⚠ SIMULATE THE PROBLEM ⚠
# Delete the app the WRONG way: remove the App Registration (which cascades
# the service principal) WITHOUT removing the role assignment first.
# Result: an ORPHANED role assignment — shown as "Identity not found" /
# principal type "Unknown" in the portal. This is exactly what happens in
# real tenants when apps are removed without a decommission runbook.
set -euo pipefail
source "$(dirname "$0")/../.env"
source "$(dirname "$0")/../.lab-state"

echo "==> Deleting App Registration '$LAB_APP_NAME' WITHOUT cleaning role assignments first..."
az ad app delete --id "$APP_ID"
echo "    App registration + service principal deleted (app is now in soft-delete for 30 days)."

echo ""
echo "==> Waiting a moment for directory propagation..."
sleep 20

SUB_ID=$(az account show --query id -o tsv)
SCOPE="/subscriptions/$SUB_ID/resourceGroups/$LAB_RG"

echo "==> Role assignments still present at $SCOPE:"
az role assignment list --scope "$SCOPE" \
  --query "[].{principalId:principalId, principalName:principalName, type:principalType, role:roleDefinitionName}" \
  --output table

echo ""
echo "    ^ Notice the assignment for principalId $SP_OBJ_ID with an EMPTY principalName."
echo "      The identity no longer exists, but the permission record remains."
echo "      Run 05-audit-orphans.sh to detect it programmatically,"
echo "      then 06-decommission.sh to clean everything up properly."
