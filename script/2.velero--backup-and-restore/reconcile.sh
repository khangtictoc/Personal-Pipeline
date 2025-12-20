#!/usr/bin/env bash

YAML_FILE=".github/workflows/2.velero--backup-and-restore.yaml"
username="github-actions[bot]"
GITHUB_REPOSITORY=$1

clusters=$(aws eks list-clusters --region "$REGION" --query "clusters" --output text)

if [ -z "$clusters" ]; then
    echo "Error: No clusters found in region $REGION"
    exit 1
fi

default_cluster=$(echo "$clusters" | awk '{print $1}')

# Set Default cluster
yq -i ".on.workflow_dispatch.inputs.cluster_name.default = \"$default_cluster\"" "$YAML_FILE"

# Append each cluster safely
yq -i ".on.workflow_dispatch.inputs.cluster_name.options = []" "$YAML_FILE"
for c in $clusters; do
    yq -i ".on.workflow_dispatch.inputs.cluster_name.options += [\"$c\"]" "$YAML_FILE"
done

echo "Updated $YAML_FILE with clusters from region $REGION"

cat $YAML_FILE

# Push changes to Pipeline Repo
git config --global user.name "github-actions[bot]"
git config --global user.email "github-actions[bot]@users.noreply.github.com"

git add .
# Only commit if there are changes to avoid "nothing to commit" errors
git diff-index --quiet HEAD || git commit -m "Update: Add cluster's names"
git push origin main