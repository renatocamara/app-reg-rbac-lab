#!/usr/bin/env bash
# 05 - AUDIT: find leftovers that outlive deleted apps. Reusable in real tenants.
#   (1) Orphaned RBAC role assignments (principal no longer exists)
#   (2) Soft-deleted app registrations still restorable
#   (3) App registrations with expired secrets/certs or with no owners
set -euo pipefail
source "$(dirname "$0")/../.env" 2>/dev/null || true

SUB_ID=$(az account show --query id -o tsv)

echo "=========================================================="
echo " (1) ORPHANED ROLE ASSIGNMENTS in subscription $SUB_ID"
echo "     (principalName empty => identity was deleted)"
echo "=========================================================="
az role assignment list --all \
  --query "[?principalName==''].{principalId:principalId, role:roleDefinitionName, scope:scope}" \
  --output table

echo ""
echo "=========================================================="
echo " (2) SOFT-DELETED APP REGISTRATIONS (restorable for 30 days)"
echo "=========================================================="
az rest --method GET \
  --url "https://graph.microsoft.com/v1.0/directory/deletedItems/microsoft.graph.application?\$select=id,appId,displayName,deletedDateTime" \
  | jq -r '.value[] | [.displayName, .appId, .deletedDateTime] | @tsv' \
  | column -t -s $'\t' || echo "(none)"

echo ""
echo "=========================================================="
echo " (3) APP HYGIENE: expired credentials and ownerless apps"
echo "=========================================================="
NOW=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

echo "--- Apps with EXPIRED password credentials ---"
az ad app list --all \
  --query "[?passwordCredentials[?endDateTime < '$NOW']].{name:displayName, appId:appId}" \
  --output table

echo ""
echo "--- Apps with NO owners ---"
for row in $(az ad app list --all --query "[].{id:id}" -o tsv); do
  OWNERS=$(az rest --method GET \
    --url "https://graph.microsoft.com/v1.0/applications/$row/owners?\$select=id" \
    --query "length(value)" -o tsv 2>/dev/null || echo "?")
  if [[ "$OWNERS" == "0" ]]; then
    az ad app show --id "$row" --query "{name:displayName, appId:appId}" -o tsv
  fi
done | column -t || echo "(none)"

echo ""
echo "=========================================================="
echo " (4) CUSTOM ROLES WITH STALE ASSIGNABLE SCOPES"
echo "     (subscriptions referenced in assignableScopes that are"
echo "      not visible in this tenant: deleted or inaccessible)"
echo "=========================================================="
VISIBLE_SUBS=$(az account list --all --query '[].id' -o tsv)
az role definition list --custom-role-only true \
  --query '[].{name:roleName, scopes:assignableScopes}' -o json \
| jq -r '.[] | .name as $n | .scopes[] | select(startswith("/subscriptions/")) | [$n, (split("/")[2])] | @tsv' \
| sort -u \
| while IFS=$'\t' read -r ROLE SCOPE_SUB; do
    if ! grep -q "$SCOPE_SUB" <<< "$VISIBLE_SUBS"; then
      echo "STALE?  role='$ROLE'  subscription=$SCOPE_SUB"
    fi
  done
echo "(no output above = nothing stale)"
echo "NOTE: removing a subscription from assignableScopes FAILS with"
echo "      RoleScopeBeingRemovedContainsAssignments while role assignments"
echo "      still exist at that scope. Delete the assignments first. If the"
echo "      subscription was already deleted and backend references are stuck,"
echo "      a Microsoft support case (Product Group cleanup) is required."

echo ""
echo "==> Audit complete. Anything listed above needs an owner, a cleanup, or a decommission."
