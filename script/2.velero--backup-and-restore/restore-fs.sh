#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
#  Velero Restore Script — EKS / Kopia (fs-backup)
#  Usage: ./velero-restore.sh <backup-name> [namespace]
#  
#  Examples:
#    ./velero-restore.sh my-backup              # restore all namespaces
#    ./velero-restore.sh my-backup jenkins      # restore jenkins only
# ─────────────────────────────────────────────────────────────

# ── Colors ────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log_info()    { echo -e "${CYAN}[INFO] $*${NC}"; }
log_success() { echo -e "${GREEN}[SUCCESS] $*${NC}"; }
log_warn()    { echo -e "${YELLOW}[WARN] $*${NC}"; }
log_error()   { echo -e "${RED}[ERROR] $*${NC}" >&2; }
log_step()    { echo -e "\n${BOLD}━━━ $* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# ── Args & Validation ─────────────────────────────────────────
BACKUP_NAME="${1:-}"
TARGET_NAMESPACE="${2:-}"           # optional — empty means all namespaces
RESTORE_NAME="${BACKUP_NAME}-restore-$(date +%Y%m%d-%H%M%S)"

if [[ -z "$BACKUP_NAME" ]]; then
  log_error "Backup name is required."
  echo "Usage: $0 <backup-name> [namespace]"
  echo ""
  echo "Available backups:"
  velero backup get
  exit 1
fi

# ── Check dependencies ────────────────────────────────────────
for cmd in velero kubectl jq; do
  if ! command -v "$cmd" &>/dev/null; then
    log_error "Required command not found: $cmd"
    exit 1
  fi
done

# ── Verify backup exists and is healthy ───────────────────────
log_step "Verifying Backup"
BACKUP_STATUS=$(velero backup get "$BACKUP_NAME" -o json 2>/dev/null \
  | jq -r '.status.phase' 2>/dev/null || echo "NotFound")

if [[ "$BACKUP_STATUS" != "Completed" ]]; then
  log_error "Backup '$BACKUP_NAME' is not in Completed state (status: $BACKUP_STATUS)"
  exit 1
fi
log_success "Backup '$BACKUP_NAME' verified — status: $BACKUP_STATUS"

# ── Confirm with user ─────────────────────────────────────────
log_step "Restore Plan"
if [[ -n "$TARGET_NAMESPACE" ]]; then
  log_warn "Target    : namespace '$TARGET_NAMESPACE' only"
  log_warn "⚠️  Namespace '$TARGET_NAMESPACE' will be DELETED and recreated from backup."
else
  log_warn "Target    : ALL namespaces in backup '$BACKUP_NAME'"
  log_warn "⚠️  All included namespaces will be DELETED and recreated from backup."
fi
log_info  "Restore name : $RESTORE_NAME"

# ── Delete namespace(s) for clean restore ─────────────────────
log_step "Preparing Clean State"

delete_and_wait_namespace() {
  local ns="$1"
  if kubectl get namespace "$ns" &>/dev/null; then
    log_warn "Deleting namespace '$ns' for clean restore..."
    kubectl delete namespace "$ns" --timeout=60s || true

    log_info "Waiting for namespace '$ns' to be fully removed..."
    local timeout=180
    local elapsed=0
    while kubectl get namespace "$ns" &>/dev/null; do
      if (( elapsed >= timeout )); then
        log_warn "Namespace '$ns' taking long to delete — checking for stuck resources..."
        # Remove finalizers if stuck
        kubectl get namespace "$ns" -o json \
          | jq '.spec.finalizers = []' \
          | kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f - &>/dev/null || true
      fi
      sleep 3
      (( elapsed += 3 ))
      echo -ne "\r  Waiting... ${elapsed}s"
    done
    echo ""
    log_success "Namespace '$ns' deleted."
  else
    log_info "Namespace '$ns' does not exist — clean state confirmed."
  fi
}

if [[ -n "$TARGET_NAMESPACE" ]]; then
  delete_and_wait_namespace "$TARGET_NAMESPACE"
else
  # Get all namespaces from the backup and delete them
  BACKUP_NAMESPACES=$(velero backup describe "$BACKUP_NAME" --details \
    | grep -A100 "Namespaces:" | grep "Included:" | head -1 \
    | sed 's/.*Included: //' | tr ',' '\n' | tr -d ' ')

  if [[ "$BACKUP_NAMESPACES" == "all namespaces found in the backup" ]] || \
     [[ "$BACKUP_NAMESPACES" == "*" ]]; then
    # Get actual namespaces from backup resource list
    BACKUP_NAMESPACES=$(velero backup describe "$BACKUP_NAME" --details \
      | grep "Namespace:" | awk '{print $2}' | sort -u)
  fi

  for ns in $BACKUP_NAMESPACES; do
    # Skip system namespaces
    case "$ns" in
      kube-system|kube-public|kube-node-lease|velero) 
        log_info "Skipping system namespace: $ns"
        continue ;;
    esac
    delete_and_wait_namespace "$ns"
  done
fi

# ── Run Restore ───────────────────────────────────────────────
log_step "Starting Restore"

RESTORE_ARGS=(
  velero restore create "$RESTORE_NAME"
  --from-backup "$BACKUP_NAME"
)

if [[ -n "$TARGET_NAMESPACE" ]]; then
  RESTORE_ARGS+=(--include-namespaces "$TARGET_NAMESPACE")
fi

# Submit restore (non-blocking so we can stream logs)
"${RESTORE_ARGS[@]}"
log_info "Restore '$RESTORE_NAME' submitted. Streaming logs...\n"

# ── Stream logs in real-time ──────────────────────────────────
log_step "Live Restore Logs"

# Wait for restore to have logs available
sleep 3
ATTEMPTS=0
while ! velero restore logs "$RESTORE_NAME" &>/dev/null; do
  sleep 2
  (( ATTEMPTS++ ))
  if (( ATTEMPTS > 15 )); then
    log_warn "Logs not available yet — restore may still be initializing..."
    break
  fi
done

# Stream logs with color highlighting
velero restore logs "$RESTORE_NAME" --follow 2>/dev/null \
  | while IFS= read -r line; do
      if echo "$line" | grep -q '"level":"error"\|level=error'; then
        echo -e "${RED}$line${NC}"
      elif echo "$line" | grep -q '"level":"warning"\|level=warning'; then
        echo -e "${YELLOW}$line${NC}"
      elif echo "$line" | grep -q 'Restored [0-9]* items'; then
        echo -e "${GREEN}$line${NC}"
      elif echo "$line" | grep -q 'pod volume\|kopia\|PodVolumeRestore'; then
        echo -e "${CYAN}$line${NC}"
      else
        echo "$line"
      fi
    done

# ── Wait for completion ───────────────────────────────────────
log_step "Waiting for Full Completion"
log_info "Waiting for restore and pod volume restores (Kopia) to finish..."

TIMEOUT=1800   # 30 min max
ELAPSED=0
INTERVAL=10

while true; do
  PHASE=$(velero restore get "$RESTORE_NAME" -o json \
    | jq -r '.status.phase' 2>/dev/null || echo "Unknown")

  PVR_PENDING=$(kubectl get podvolumerestores -n velero \
    --field-selector=metadata.name="$RESTORE_NAME" \
    -o json 2>/dev/null \
    | jq '[.items[] | select(.status.phase != "Completed")] | length' \
    2>/dev/null || echo "0")

  echo -ne "\r  Phase: ${BOLD}$PHASE${NC} | Pending PodVolumeRestores: $PVR_PENDING | Elapsed: ${ELAPSED}s   "

  if [[ "$PHASE" == "Completed" || "$PHASE" == "PartiallyFailed" || "$PHASE" == "Failed" ]]; then
    echo ""
    break
  fi

  if (( ELAPSED >= TIMEOUT )); then
    echo ""
    log_error "Restore timed out after ${TIMEOUT}s"
    break
  fi

  sleep "$INTERVAL"
  (( ELAPSED += INTERVAL ))
done

# ── Results ───────────────────────────────────────────────────
log_step "Restore Results"

FINAL_PHASE=$(velero restore get "$RESTORE_NAME" -o json | jq -r '.status.phase')
ERRORS=$(velero restore get "$RESTORE_NAME" -o json | jq -r '.status.errors // 0')
WARNINGS=$(velero restore get "$RESTORE_NAME" -o json | jq -r '.status.warnings // 0')

velero restore describe "$RESTORE_NAME"

echo ""
if [[ "$FINAL_PHASE" == "Completed" && "$ERRORS" == "0" ]]; then
  log_success "Restore completed successfully!"
  log_info    "Errors: $ERRORS | Warnings: $WARNINGS"
elif [[ "$FINAL_PHASE" == "Completed" ]]; then
  log_warn    "Restore completed with warnings."
  log_info    "Errors: $ERRORS | Warnings: $WARNINGS"
  log_warn    "Check warnings above — volume data may not have been fully restored."
else
  log_error   "Restore phase: $FINAL_PHASE | Errors: $ERRORS | Warnings: $WARNINGS"
  exit 1
fi

# ── Verify Kopia actually ran ─────────────────────────────────
log_step "Verifying Volume Restore (Kopia)"

PVR_COUNT=$(kubectl get podvolumerestores -n velero -o json 2>/dev/null \
  | jq '[.items[]] | length' 2>/dev/null || echo "0")

if [[ "$PVR_COUNT" == "0" ]]; then
  log_warn "No PodVolumeRestores found — Kopia did NOT run!"
  log_warn "Volume data was NOT restored from S3."
  log_warn "This usually means the namespace was not fully deleted before restore."
else
  log_info "PodVolumeRestores found: $PVR_COUNT"
  kubectl get podvolumerestores -n velero
  
  FAILED_PVR=$(kubectl get podvolumerestores -n velero -o json \
    | jq '[.items[] | select(.status.phase == "Failed")] | length')
  
  if [[ "$FAILED_PVR" -gt 0 ]]; then
    log_error "$FAILED_PVR PodVolumeRestore(s) failed — some volume data may be missing!"
  else
    log_success "All PodVolumeRestores completed successfully ✅"
  fi
fi

# ── Post-restore health check ─────────────────────────────────
log_step "Post-Restore Health Check"

CHECK_NS="${TARGET_NAMESPACE:-$(kubectl get ns -o jsonpath='{.items[*].metadata.name}')}"

log_info "Checking pod status in restored namespaces..."
if [[ -n "$TARGET_NAMESPACE" ]]; then
  kubectl get pods -n "$TARGET_NAMESPACE"
else
  kubectl get pods -A | grep -v -E "kube-system|kube-public|velero|Running|Completed"
fi

echo ""
log_info "Checking PVC status..."
if [[ -n "$TARGET_NAMESPACE" ]]; then
  kubectl get pvc -n "$TARGET_NAMESPACE"
else
  kubectl get pvc -A
fi