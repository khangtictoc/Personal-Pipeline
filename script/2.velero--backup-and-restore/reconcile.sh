#!/usr/bin/env bash

# ==============================================================================
# Velero Workflow Reconciler (Cloud-Agnostic)
# Synchronizes K8s Cluster names and Velero Backup versions into GitHub Actions
# ==============================================================================

YAML_FILE=".github/workflows/2.velero--backup-and-restore.yaml"
username="github-actions[bot]"
GITHUB_REPOSITORY=$1
PAGER_SIZE=10

function reconcile-backup-versions(){
    log_info "Fetching latest $PAGER_SIZE completed backups from Velero..."

    # Unified Velero CLI call: ignores provider specifics, focuses on status
    versions=$(velero backup get \
        --sort-column "start time" \
        -o jsonpath='{range .items[?(@.status.phase=="Completed")]}{.metadata.name}{"\n"}{end}' \
        | tac | head -n "$PAGER_SIZE")

    if [ -z "$versions" ]; then
        log_error "No 'Completed' backups found in the Velero registry."
        exit 1
    fi

    # The most recent successful backup becomes the default
    default_version=$(echo "$versions" | head -n1)

    log_info "Synchronizing workflow dispatch inputs in YAML..."
    
    # Update Default version
    yq -i ".on.workflow_dispatch.inputs.restored_version.default = \"$default_version\"" "$YAML_FILE"
    
    # Refresh the options array
    yq -i ".on.workflow_dispatch.inputs.restored_version.options = []" "$YAML_FILE"
    
    for v in $versions; do
        yq -i ".on.workflow_dispatch.inputs.restored_version.options += [\"$v\"]" "$YAML_FILE"
    done

    log_success "Successfully synced $PAGER_SIZE latest backup records to $YAML_FILE"
}

function reconcile-cluster-names(){
    log_info "Detecting available clusters..."
    
    # Note: Keep the AWS call here for cluster discovery if running on EKS, 
    # or swap for 'kubectl config get-contexts' for a fully generic approach.
    clusters=$(aws eks list-clusters --region "$REGION" --query "clusters" --output text | tr '\t' '\n')

    if [ -z "$clusters" ]; then
        log_error "No clusters detected for region $REGION"
        exit 1
    fi

    default_cluster=$(echo "$clusters" | head -n1)

    # Sync cluster inputs to YAML
    yq -i ".on.workflow_dispatch.inputs.cluster_name.default = \"$default_cluster\"" "$YAML_FILE"
    yq -i ".on.workflow_dispatch.inputs.cluster_name.options = []" "$YAML_FILE"

    for c in $clusters; do
        yq -i ".on.workflow_dispatch.inputs.cluster_name.options += [\"$c\"]" "$YAML_FILE"
    done

    log_success "Cluster list reconciled for region $REGION"
}

function update-repo-changes(){
    log_highlight "--------------------------------------------------------"
    log_info "Reviewing Workflow Updates:"
    cat "$YAML_FILE"
    log_highlight "--------------------------------------------------------"

    git config --global user.name "$username"
    git config --global user.email "github-actions[bot]@users.noreply.github.com"
    
    log_info "Preparing Git commit..."
    git add "$YAML_FILE"
    
    if git diff --staged --quiet; then
        log_warn "No delta detected in $YAML_FILE. Skipping push."
    else
        git commit -m "chore: auto-reconcile clusters and backup versions"
        git remote set-url origin "https://$username:$GH_TOKEN@github.com/$GITHUB_REPOSITORY.git"
        git push
        log_success "Repository updated with latest available versions."
    fi
}

function main(){
    source <(curl -sS https://raw.githubusercontent.com/khangtictoc/Productive-Workspace-Set-Up/refs/heads/main/linux/utility/library/bash/ansi_color.sh)
    init-ansicolor

    log_highlight "========================================================"
    log_highlight "  VELERO METADATA RECONCILER"
    log_highlight "========================================================"

    reconcile-cluster-names
    reconcile-backup-versions
    update-repo-changes

    log_highlight "========================================================"
}

main "$@"