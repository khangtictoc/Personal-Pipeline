#!/usr/bin/env bash
set -euo pipefail

# Disable AWS CLI pager globally
export AWS_PAGER=""
export AWS_CLI_PAGER=""

TABLE="$2"
REGION="$1"

echo "[INFO] Scanning DynamoDB table: $TABLE in region $REGION"

# Find all LockIDs where Info exists and is not empty
LOCKS=$(aws dynamodb scan \
  --table-name "$TABLE" \
  --region "$REGION" \
  --filter-expression "attribute_exists(Info) AND Info <> :empty" \
  --expression-attribute-values '{":empty":{"S":""}}' \
  --query "Items[].LockID.S" \
  --output text)

if [[ -z "$LOCKS" ]]; then
  echo "[INFO] No active locks found (Info field empty). Nothing to delete."
else
  echo "[INFO] Found locks to delete:"
  for lockid in $LOCKS; do
    echo "  - $lockid"
    aws dynamodb delete-item \
      --table-name "$TABLE" \
      --region "$REGION" \
      --key "{\"LockID\": {\"S\": \"$lockid\"}}" || true
    echo "[INFO] Deleted lock: $lockid"
  done
fi

echo "[INFO] Cleanup finished."
