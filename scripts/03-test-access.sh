#!/usr/bin/env bash
# 03 - Prove the RBAC works: log in AS the service principal and:
#   (a) successfully list blobs in the lab container  -> role grants this
#   (b) FAIL to write a blob                          -> Reader role denies this
# The negative test matters: least privilege means proving what is DENIED too.
set -euo pipefail
source "$(dirname "$0")/../.env"
source "$(dirname "$0")/../.lab-state"

echo "==> Logging in as the service principal (isolated az context)..."
export AZURE_CONFIG_DIR="$(mktemp -d)"   # don't touch your user session
az login --service-principal \
  --username "$APP_ID" \
  --password "$SECRET" \
  --tenant "$TENANT_ID" \
  --output none

echo ""
echo "==> [POSITIVE TEST] Listing containers with --auth-mode login..."
az storage container list \
  --account-name "$LAB_STORAGE_ACTUAL" \
  --auth-mode login \
  --query "[].name" -o tsv \
  && echo "    PASS: read access works via RBAC."

echo ""
echo "==> [NEGATIVE TEST] Trying to CREATE a container (should be DENIED)..."
if az storage container create \
     --name "should-fail" \
     --account-name "$LAB_STORAGE_ACTUAL" \
     --auth-mode login \
     --output none 2>/dev/null; then
  echo "    UNEXPECTED: write succeeded — check the assigned role!"
  exit 1
else
  echo "    PASS: write denied, as expected for 'Storage Blob Data Reader'."
fi

az logout --output none || true
rm -rf "$AZURE_CONFIG_DIR"
unset AZURE_CONFIG_DIR
echo ""
echo "==> Done. Least privilege verified (allowed what it should, denied what it shouldn't)."
