#!/bin/bash

# ==============================================================================
# Velero Namespace Backup Script
# Usage: ./backup.sh <cluster_name> <namespaces_list>
# ==============================================================================

# 1. Source remote utility and initialize colors
# We use a subshell to ensure sourcing happens before any logging
source <(curl -sS https://raw.githubusercontent.com/khangtictoc/Productive-Workspace-Set-Up/refs/heads/main/linux/utility/library/bash/ansi_color.sh)
init-ansicolor

# 2. Validation
if [ "$#" -ne 2 ]; then
    log_error "Missing arguments."
    log_info "Usage: $0 <clustername> <namespaces_list>"
    log_info "Example: $0 Production \"jenkins,postgres\""
    exit 1
fi

if ! command -v velero &> /dev/null; then
    log_error "Velero CLI is not installed or not in PATH."
    exit 1
fi

# 3. Variables & Formatting
CLUSTER_NAME="$1"
NAMESPACES="$2"
CURRENT_TIME=$(date +"%Y.%m.%d-%H.%M.%S")

# Format cluster name: lowercase and DNS-compliant (replace underscores/spaces)
CLUSTER_NAME_FORMATTED=$(echo "$CLUSTER_NAME" | tr '[:upper:]' '[:lower:]' | tr '_ ' '-')
BACKUP_NAME="$CLUSTER_NAME_FORMATTED-$CURRENT_TIME"

log_highlight "--------------------------------------------------------"
log_info "Initiating backup for cluster: $CLUSTER_NAME"
log_info "Target Backup Name: $BACKUP_NAME"
log_info "Namespaces: $NAMESPACES"
log_highlight "--------------------------------------------------------"

# 4. Check if backup name already exists
if velero backup get "$BACKUP_NAME" &> /dev/null; then
    log_error "A backup named '$BACKUP_NAME' already exists in the cluster."
    log_warn "Wait a moment for the timestamp to increment or check existing backups."
    exit 1
fi

# 5. Execute Backup
log_info "Status: Requesting Velero backup (Defaulting to Filesystem Backup)..."
velero backup create "$BACKUP_NAME" \
    --include-namespaces "$NAMESPACES" \
    --wait

# 6. Verification
log_highlight "--------------------------------------------------------"
log_info "VERIFICATION PHASE"
log_highlight "--------------------------------------------------------"

# Check Phase
BACKUP_STATUS=$(velero backup get "$BACKUP_NAME" -o jsonpath='{.status.phase}')

if [ "$BACKUP_STATUS" == "Completed" ]; then
    log_success "Backup '$BACKUP_NAME' completed successfully!"
elif [ "$BACKUP_STATUS" == "PartiallyFailed" ]; then
    log_warn "Backup '$BACKUP_NAME' finished with status: PartiallyFailed. Check details below."
else
    log_error "Backup '$BACKUP_NAME' failed with status: $BACKUP_STATUS"
    exit 1
fi

# 7. Data Movement Summary (Kopia/PVB details)
log_info "Data Movement Summary (PodVolumeBackups):"
kubectl get podvolumebackups -n velero -l velero.io/backup-name="$BACKUP_NAME"

# 8. Log Review
ERRORS=$(velero backup logs "$BACKUP_NAME" | grep -i "error" || true)
if [ -n "$ERRORS" ]; then
    log_error "Anomalies found in Velero logs:"
    echo "$ERRORS"
else
    log_success "No errors found in backup logs."
fi

log_highlight "--------------------------------------------------------"
log_info "Script Execution Finished."