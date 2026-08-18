#!/usr/bin/env bash
# 02 - Grant least-privilege RBAC to the service principal.
# Teaching points:
#   - Assign to the SERVICE PRINCIPAL, at the NARROWEST useful scope (RG here,
#     could be the storage account itself for even tighter scoping).
#   - Use a data-plane role (Storage Blob Data Reader), not Contributor/Owner.
set -euo pipefail
source "$(dirname "$0")/../.env"
source "$(dirname "$0")/../.lab-state"

SUB_ID=$(az account show --query id -o tsv)
SCOPE="/subscriptions/$SUB_ID/resourceGroups/$LAB_RG"

echo "==> Assigning role '$LAB_ROLE' to SP $SP_OBJ_ID at scope $SCOPE..."
az role assignment create \
  --assignee-object-id "$SP_OBJ_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "$LAB_ROLE" \
  --scope "$SCOPE" \
  --output table

echo ""
echo "==> Current role assignments at this scope for the SP:"
az role assignment list --assignee "$APP_ID" --all --output table

echo ""
echo "==> Done. RBAC can take ~1-5 minutes to propagate before the test works."
