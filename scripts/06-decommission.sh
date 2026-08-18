#!/usr/bin/env bash
# 06 - THE CORRECT DECOMMISSION RUNBOOK.
# Works in both situations:
#   - App still exists (Path B: skipped script 04) -> full ordered teardown
#   - App already deleted the wrong way (Path A)   -> cleans the orphan + purge
#
# Correct order:
#   1. Remove RBAC role assignments        (by principalId — works even if orphaned)
#   2. Revoke OAuth2 grants / app role assignments (if SP still exists)
#   3. Delete service principal
#   4. Delete app registration
#   5. Purge from soft-delete (after validation window, if policy allows)
#   6. Review directory roles granted to HUMANS because of this app (manual/PIM)
set -euo pipefail
source "$(dirname "$0")/../.env"
source "$(dirname "$0")/../.lab-state"

SUB_ID=$(az account show --query id -o tsv)

echo "==> [1/6] Removing ALL role assignments for principal $SP_OBJ_ID (works even for orphans)..."
ASSIGNMENT_IDS=$(az role assignment list --all \
  --query "[?principalId=='$SP_OBJ_ID'].id" -o tsv)
if [[ -n "$ASSIGNMENT_IDS" ]]; then
  while IFS= read -r aid; do
    az role assignment delete --ids "$aid" --output none
    echo "    removed: $aid"
  done <<< "$ASSIGNMENT_IDS"
else
  echo "    none found."
fi

echo "==> [2/6] Revoking OAuth2 grants / app role assignments (if SP still exists)..."
if az ad sp show --id "$SP_OBJ_ID" --output none 2>/dev/null; then
  GRANTS=$(az rest --method GET \
    --url "https://graph.microsoft.com/v1.0/servicePrincipals/$SP_OBJ_ID/oauth2PermissionGrants" \
    --query "value[].id" -o tsv)
  for g in $GRANTS; do
    az rest --method DELETE --url "https://graph.microsoft.com/v1.0/oauth2PermissionGrants/$g"
    echo "    revoked grant: $g"
  done

  echo "==> [3/6] Deleting service principal..."
  az ad sp delete --id "$SP_OBJ_ID"

  echo "==> [4/6] Deleting app registration..."
  az ad app delete --id "$APP_ID" 2>/dev/null || echo "    (already deleted)"
else
  echo "    SP already gone — skipping [2/6] and [3/6]."
  echo "==> [4/6] App registration already deleted (Path A)."
fi

echo "==> [5/6] Purging the app from soft-delete..."
DELETED_ID=$(az rest --method GET \
  --url "https://graph.microsoft.com/v1.0/directory/deletedItems/microsoft.graph.application" \
  --query "value[?appId=='$APP_ID'].id | [0]" -o tsv)
if [[ -n "$DELETED_ID" && "$DELETED_ID" != "None" ]]; then
  az rest --method DELETE \
    --url "https://graph.microsoft.com/v1.0/directory/deletedItems/$DELETED_ID"
  echo "    purged: $DELETED_ID"
else
  echo "    nothing in soft-delete for appId $APP_ID."
fi

echo "==> [6/6] MANUAL STEP — review humans:"
echo "    - Was anyone given Application Administrator / Cloud Application Administrator"
echo "      because of this app? If no longer justified, remove the assignment or"
echo "      the PIM-eligible group membership."
echo "    - Check: az rest --method GET --url \"https://graph.microsoft.com/v1.0/directoryRoles(roleTemplateId='9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3')/members\""
echo ""
echo "==> Decommission complete. Re-run 05-audit-orphans.sh to confirm a clean state."
