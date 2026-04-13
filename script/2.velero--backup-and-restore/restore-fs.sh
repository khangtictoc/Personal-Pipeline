#!/usr/bin/env bash

# ==============================================================================
# Velero Restore Engine
# Usage: ./restore.sh <backup_name>
# ==============================================================================

function draw_header() {
    local title=$1
    log_highlight "--------------------------------------------------------"
    log_highlight "  $title"
    log_highlight "--------------------------------------------------------"
}

function execute-restore(){
    local backup_name=$1
    # Appending timestamp ensures uniqueness; Velero won't allow duplicate restore names.
    local restore_name="restore-${backup_name}-$(date +%s)"

    draw_header "VELERO RESTORE INITIATED"
    log_info "Target Backup:  $backup_name"
    log_info "Restore ID:     $restore_name"
    echo ""

    # 1. Pre-flight Validation
    log_info "Status: Validating backup registry record..."
    local backup_phase=$(velero backup get "$backup_name" -o jsonpath='{.status.phase}' 2>/dev/null)

    if [[ -z "$backup_phase" ]]; then
        log_error "Backup '$backup_name' not found. Ensure the record exists in the current cluster context."
        exit 1
    fi

    if [[ "$backup_phase" != "Completed" ]]; then
        log_warn "Warning: The source backup status is '$backup_phase'. Proceeding with caution."
    fi

    # 2. Execution
    log_info "Status: Submitting restore request and waiting for completion..."
    velero restore create "$restore_name" \
        --from-backup "$backup_name" \
        --wait

    # 3. Verification Phase
    echo ""
    draw_header "RESTORE VERIFICATION"
    
    local restore_phase=$(velero restore get "$restore_name" -o jsonpath='{.status.phase}')

    if [[ "$restore_phase" == "Completed" ]]; then
        log_success "Restore Task finalized successfully."
    elif [[ "$restore_phase" == "PartiallyFailed" ]]; then
        log_warn "Restore finished with warnings (PartiallyFailed). Reviewing logs is recommended."
    else
        log_error "Restore Task failed with phase: $restore_phase"
        log_info "Command for logs: velero restore logs $restore_name"
        exit 1
    fi

    # 4. Filesystem Data Check
    # Since you are using Kopia, it is important to check the PodVolumeRestores
    log_info "Checking Pod Volume Restore status..."
    kubectl get podvolumerestores -n velero -l velero.io/restore-name="$restore_name" 2>/dev/null || log_info "No filesystem volumes to restore."
}

function main(){
    # Source remote utility
    source <(curl -sS https://raw.githubusercontent.com/khangtictoc/Productive-Workspace-Set-Up/refs/heads/main/linux/utility/library/bash/ansi_color.sh)
    init-ansicolor

    if [[ -z "$1" ]]; then
        log_error "Missing Argument: Please provide the backup name."
        log_info "Usage: $0 <backup_name>"
        exit 1
    fi

    execute-restore "$1"
    
    log_highlight "--------------------------------------------------------"
    log_success "Operation Complete."
    log_highlight "--------------------------------------------------------"
}

main "$@"