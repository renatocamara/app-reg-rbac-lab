#!/usr/bin/env bash
# 01 - Create the App Registration and its Service Principal.
# Key teaching point: these are TWO different objects.
#   - App Registration (application object)  -> the app's definition
#   - Service Principal (enterprise app)     -> the identity that gets RBAC
set -euo pipefail
source "$(dirname "$0")/../.env"
STATE="$(dirname "$0")/../.lab-state"
source "$STATE"

echo "==> Creating App Registration '$LAB_APP_NAME'..."
APP_ID=$(az ad app create \
  --display-name "$LAB_APP_NAME" \
  --sign-in-audience AzureADMyOrg \
  --query appId -o tsv)
APP_OBJ_ID=$(az ad app show --id "$APP_ID" --query id -o tsv)
echo "    appId (client id):        $APP_ID"
echo "    application object id:    $APP_OBJ_ID"

echo "==> Creating the Service Principal for it..."
SP_OBJ_ID=$(az ad sp create --id "$APP_ID" --query id -o tsv)
echo "    service principal id:     $SP_OBJ_ID"

echo "==> Creating a client secret (lab only — prefer federated credentials / managed identity in production)..."
# Short lifetime on purpose: credentials should expire fast.
SECRET=$(az ad app credential reset \
  --id "$APP_ID" \
  --display-name "lab-secret" \
  --years 0 --end-date "$(date -u -d '+1 day' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -v+1d '+%Y-%m-%dT%H:%M:%SZ')" \
  --query password -o tsv)

TENANT_ID=$(az account show --query tenantId -o tsv)

{
  grep -v -e '^APP_ID=' -e '^APP_OBJ_ID=' -e '^SP_OBJ_ID=' -e '^TENANT_ID=' -e '^SECRET=' "$STATE" || true
  echo "APP_ID=$APP_ID"
  echo "APP_OBJ_ID=$APP_OBJ_ID"
  echo "SP_OBJ_ID=$SP_OBJ_ID"
  echo "TENANT_ID=$TENANT_ID"
  echo "SECRET=$SECRET"
} > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
chmod 600 "$STATE"

echo "==> Done. Secret stored in .lab-state (gitignored, chmod 600, expires in 24h)."
echo "    NOTE: at this point the app has ZERO access to anything. RBAC comes next."
