#!/usr/bin/env bash
set -euo pipefail

# Disable AWS CLI pager globally
export AWS_PAGER=""
export AWS_CLI_PAGER=""

PATH_TO_TERRAGRUNT_DIR="${1:-.}"

REGION="us-east-1"
LOCK_TABLE="terragrunt-state-lock"   # replace with your DynamoDB table name

# Function to find current lock ID in DynamoDB
get_lock_id() {
  aws dynamodb scan \
    --table-name "${LOCK_TABLE}" \
    --region "${REGION}" \
    --query "Items[0].LockID.S" \
    --output text 2>/dev/null || true
}

# Cleanup function to force unlock
cleanup() {
  echo "[INFO] Caught signal, attempting to force unlock..."
  LOCK_ID=$(get_lock_id)
  if [[ -n "${LOCK_ID}" && "${LOCK_ID}" != "None" ]]; then
    echo "[INFO] Found lock ID: ${LOCK_ID}, unlocking..."
    terraform force-unlock -force "${LOCK_ID}" || true
  else
    echo "[INFO] No lock ID found, nothing to unlock."
  fi
}

# Trap signals (SIGINT = Ctrl+C, SIGTERM = GitHub Actions cancel)
trap cleanup SIGINT SIGTERM

echo "[INFO] Starting Terragrunt destroy..."

cd "${PATH_TO_TERRAGRUNT_DIR}"
terragrunt run-all destroy --non-interactive \
    --queue-include-external \
    --working-dir .
