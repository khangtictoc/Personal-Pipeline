#!/usr/bin/env bash

# ==============================================================================
# Velero Restore Engine (with Pre-Restore Cleanup)
# Usage: ./restore.sh <backup_name>
# ==============================================================================

function force-delete-stuck-namespaces() {
    local timeout=${1:-300}  # default 5 minutes
    shift
    local namespaces="$@"

    local stuck_namespaces=()
    local start_time=$(date +%s)

    log_info "Waiting up to ${timeout}s for namespaces to terminate..."

    for ns in $namespaces; do
        while kubectl get namespace "$ns" >/dev/null 2>&1; do
            local now=$(date +%s)
            local elapsed=$((now - start_time))
            if [[ "$elapsed" -ge "$timeout" ]]; then
                log_warn "Timeout reached: namespace '$ns' still terminating – forcing finalizer removal."
                stuck_namespaces+=("$ns")
                break
            fi
            sleep 5
        done
    done

    if [[ ${#stuck_namespaces[@]} -eq 0 ]]; then
        return 0
    fi

    log_warn "Force-removing finalizers for stuck namespaces: ${stuck_namespaces[*]}..."

    kubectl proxy --port=8001 &
    local proxy_pid=$!
    sleep 2

    for ns in "${stuck_namespaces[@]}"; do
        log_info "Purging finalizers from namespace '$ns'..."
        kubectl get namespace "$ns" -o json | jq '.spec = {"finalizers":[]}' > "/tmp/ns-${ns}-finalize.json"
        curl -s -k -H "Content-Type: application/json" \
             -X PUT \
             --data-binary @"/tmp/ns-${ns}-finalize.json" \
             "http://127.0.0.1:8001/api/v1/namespaces/${ns}/finalize" \
             > /dev/null 2>&1
        rm -f "/tmp/ns-${ns}-finalize.json"
    done

    kill "$proxy_pid" 2>/dev/null
    wait "$proxy_pid" 2>/dev/null

    sleep 10
    for ns in "${stuck_namespaces[@]}"; do
        if kubectl get namespace "$ns" >/dev/null 2>&1; then
            log_error "Namespace '$ns' could not be removed even after finalizer purge."
        else
            log_success "Namespace '$ns' successfully removed."
        fi
    done
}

function draw_header() {
    local title=$1
    log_highlight "--------------------------------------------------------"
    log_highlight "  $title"
    log_highlight "--------------------------------------------------------"
}

function execute-restore(){
    local backup_name=$1
    local restore_name="restore-${backup_name}-$(date +%s)"

    draw_header "VELERO RESTORE INITIATED"
    log_info "Target Backup:  $backup_name"
    log_info "Restore ID:     $restore_name"

    # 1. Pre-flight Validation & Metadata Extraction
    log_info "Status: Validating backup and extracting namespaces..."
    local backup_json=$(velero backup get "$backup_name" -o json 2>/dev/null)
    
    if [[ -z "$backup_json" ]]; then
        log_error "Backup '$backup_name' not found."
        exit 1
    fi

    local backup_phase=$(echo "$backup_json" | jq -r '.status.phase')
    if [[ "$backup_phase" != "Completed" ]]; then
        log_warn "Warning: Source backup status is '$backup_phase'. Proceeding with caution."
    fi

    # Extract namespaces from the backup spec
    local namespaces=$(echo "$backup_json" | jq -r '.spec.includedNamespaces[]' 2>/dev/null)

    # 2. Cleanup Phase (Crucial for Clean Restore)
    if [[ ! -z "$namespaces" ]]; then
        echo ""
        draw_header "PRE-RESTORE CLEANUP"
        for ns in $namespaces; do
            if kubectl get namespace "$ns" >/dev/null 2>&1; then
                log_warn "Action: Deleting existing namespace '$ns' to prevent conflicts..."
                kubectl delete namespace "$ns" --wait=false # Using false to handle multiple NS in parallel
            else
                log_info "Status: Namespace '$ns' does not exist. No cleanup needed."
            fi
        done

        # Wait for all targeted namespaces to be fully purged
        force-delete-stuck-namespaces 300 $namespaces
        log_success "Cleanup Phase complete. Cluster is ready for restore."
    fi

    # 3. Execution
    echo ""
    draw_header "EXECUTION"
    log_info "Status: Submitting restore request and waiting for completion..."
    velero restore create "$restore_name" \
        --from-backup "$backup_name" \
        --wait

    # 4. Verification Phase
    echo ""
    draw_header "RESTORE VERIFICATION"
    
    local restore_phase=$(velero restore get "$restore_name" -o json | jq -r '.status.phase')

    if [[ "$restore_phase" == "Completed" ]]; then
        log_success "Restore Task finalized successfully."
    elif [[ "$restore_phase" == "PartiallyFailed" ]]; then
        log_warn "Restore finished with warnings (PartiallyFailed). Reviewing logs is recommended."
    else
        log_error "Restore Task failed with phase: $restore_phase"
        log_info "Command for logs: velero restore logs $restore_name"
        exit 1
    fi

    # 5. Filesystem Data Check
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