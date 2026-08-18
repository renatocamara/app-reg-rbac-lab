#!/usr/bin/env bash
# 07 - Custom Azure role for subscription cancellation (least privilege + portal visibility).
#
# Scenario (from the customer's May 12 follow-up):
#   The customer built a custom role so a small group can CANCEL subscriptions
#   without holding Owner/Contributor. Two questions came out of it:
#     1. What is the minimal set of actions the role needs?
#     2. Why do assignees need a *read* permission for the subscription to even
#        show up in the Azure portal?
#
# Teaching points:
#   - Microsoft.Subscription/cancel is the action that allows cancellation.
#   - Microsoft.Resources/subscriptions/read is what makes the subscription
#     VISIBLE in the portal (and in `az account list`). Without it, the portal
#     simply does not list the subscription for that user: they cannot navigate
#     to something they cannot read. The cancel action alone is not enough for
#     a usable workflow.
#   - assignableScopes pins where the role can be assigned (least privilege).
#   - NEVER test by actually cancelling: validate the definition, the
#     assignment, and the effective permissions instead.
#
# ⚠ This script NEVER calls the cancel action. It only creates/validates the
#   role definition and an assignment, then shows how to verify.
set -euo pipefail
source "$(dirname "$0")/../.env"
source "$(dirname "$0")/../.lab-state"

SUB_ID=$(az account show --query id -o tsv)
ROLE_NAME="${LAB_PREFIX}-subscription-canceller"

if [[ "${1:-}" == "--cleanup" ]]; then
  echo "==> Removing role assignment and custom role definition..."
  az role assignment delete --assignee "$APP_ID" --role "$ROLE_NAME" \
    --scope "/subscriptions/$SUB_ID" 2>/dev/null || true
  az role definition delete --name "$ROLE_NAME" 2>/dev/null || true
  echo "==> Done."
  exit 0
fi

echo "==> 1/4 Building the custom role definition (least privilege)..."
cat > /tmp/${ROLE_NAME}.json <<EOF
{
  "Name": "$ROLE_NAME",
  "Description": "Lab: cancel a subscription with the minimum required permissions. 'read' is required for the subscription to be visible in the portal.",
  "Actions": [
    "Microsoft.Resources/subscriptions/read",
    "Microsoft.Subscription/cancel"
  ],
  "NotActions": [],
  "AssignableScopes": [
    "/subscriptions/$SUB_ID"
  ]
}
EOF
cat /tmp/${ROLE_NAME}.json

echo ""
echo "==> 2/4 Creating the role definition..."
az role definition create --role-definition /tmp/${ROLE_NAME}.json --output table 2>/dev/null \
  || az role definition update --role-definition /tmp/${ROLE_NAME}.json --output table

echo ""
echo "==> 3/4 Assigning the role to the lab SP at subscription scope..."
az role assignment create \
  --assignee-object-id "$SP_OBJ_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "$ROLE_NAME" \
  --scope "/subscriptions/$SUB_ID" \
  --output table

echo ""
echo "==> 4/4 Validating WITHOUT cancelling anything:"
echo ""
echo "    a) Effective actions of the role:"
az role definition list --name "$ROLE_NAME" \
  --query '[0].{Role:roleName, Actions:permissions[0].actions}' -o json

echo ""
echo "    b) Assignment exists at subscription scope:"
az role assignment list --assignee "$APP_ID" \
  --scope "/subscriptions/$SUB_ID" --output table

echo ""
echo "    c) Portal visibility test (run as the assignee, e.g. after"
echo "       'az login --service-principal' like in script 03):"
echo "         az account list --output table"
echo "       With 'Microsoft.Resources/subscriptions/read' the subscription is"
echo "       listed. Remove that action from the JSON, update the role, and it"
echo "       disappears: that is exactly why the read permission is required"
echo "       for the cancellation workflow to be usable from the portal."
echo ""
echo "==> DO NOT invoke Microsoft.Subscription/cancel in a real tenant to test."
echo "    Definition + assignment + visibility is the safe validation."
echo ""
echo "==> Cleanup for this script only: $0 --cleanup"
