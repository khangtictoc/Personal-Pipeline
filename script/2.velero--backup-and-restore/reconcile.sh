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

git config --global user.name "$username"
git config --global user.email "github-actions[bot]@users.noreply.github.com"
git add .
git commit -m "Update: Add cluster's names"
git remote set-url origin https://$username:$GH_TOKEN@github.com/$GITHUB_REPOSITORY.git
git push