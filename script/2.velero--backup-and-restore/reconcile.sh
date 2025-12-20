#!/usr/bin/env bash

YAML_FILE=".github/workflows/2.velero--backup-and-restore.yaml"
username="github-actions[bot]"
S3_PATH="s3://velero-backup-kubernetes-aws/backups/"
GITHUB_REPOSITORY=$1

function reconcile-s3-velero-backup-version(){
    versions=$(aws s3api list-objects-v2 \
        --bucket velero-backup-kubernetes-aws \
        --prefix backups/ \
        --delimiter / \
        --query "reverse(sort_by(CommonPrefixes,&Prefix))[:10].Prefix" \
        --output text)

    if [ -z "$versions" ]; then
        echo "${RED}[ERROR] No backup versions found in $S3_PATH${RED}"
        exit 1
    fi

    # Clean up prefixes (remove 'backups/' suffix)
    versions=$(echo "$versions" | tr '\t' '\n' | sed 's|backups/||g' | sed 's|/||g')

    # First version becomes default
    default_version=$(echo "$versions" | head -n1)

    # Update YAML using yq
    yq -i ".on.workflow_dispatch.inputs.restored_version.default = \"$default_version\"" "$YAML_FILE"
    echo "[INFO] Updated default backup version"

    # Clear existing options
    yq -i ".on.workflow_dispatch.inputs.restored_version.options = []" "$YAML_FILE"
    echo "[INFO] Clear old existing backup versions"

    # Append each version safely
    for v in $versions; do
        yq -i ".on.workflow_dispatch.inputs.restored_version.options += [\"$v\"]" "$YAML_FILE"
    done
    echo "[INFO] Updated list of backup version"

    echo "${GREEN}[SUCCESS] Updated $YAML_FILE with 10 latest backup versions from $S3_PATH${NC}"
}

function reconcile-k8s-cluster-name(){
    clusters=$(aws eks list-clusters --region "$REGION" --query "clusters" --output text)

    if [ -z "$clusters" ]; then
        echo "${RED}[ERROR] No clusters found in region $REGION${NC}"
        exit 1
    fi

    default_cluster=$(echo "$clusters" | awk '{print $1}')

    # Set Default cluster
    yq -i ".on.workflow_dispatch.inputs.cluster_name.default = \"$default_cluster\"" "$YAML_FILE"
    echo "[INFO] Updated default cluster name"

    # Append each cluster safely
    yq -i ".on.workflow_dispatch.inputs.cluster_name.options = []" "$YAML_FILE"
    echo "[INFO] Clear old existing cluster names"

    for c in $clusters; do
        yq -i ".on.workflow_dispatch.inputs.cluster_name.options += [\"$c\"]" "$YAML_FILE"
    done
    echo "[INFO] Updated list of cluster names"

    echo "${GREEN}[SUCCESS] Updated $YAML_FILE with clusters from region $REGION${NC}"
}

function update-repo-changes(){
    cat $YAML_FILE

    git config --global user.name "$username"
    echo "[INFO] Set Git config name to gitbot user: $username"
    git config --global user.email "github-actions[bot]@users.noreply.github.com"
    echo "[INFO] Set Git config email to gitbot email: github-actions[bot]@users.noreply.github.com"
    
    echo "[INFO] Starting pushing commit ..."
    git add .
    git commit -m "Update: Add cluster's names"
    git remote set-url origin https://$username:$GH_TOKEN@github.com/$GITHUB_REPOSITORY.git
    git push
    echo "${GREEN}[SUCCESS] Push completed!${NC}"
}

function main(){
    source <(curl -sS https://raw.githubusercontent.com/khangtictoc/Productive-Workspace-Set-Up/refs/heads/main/linux/utility/library/bash/ansi_color.sh)
    init-ansicolor

    reconcile-k8s-cluster-name
    reconcile-s3-velero-backup-version
    update-repo-changes
}

main "$@" 

