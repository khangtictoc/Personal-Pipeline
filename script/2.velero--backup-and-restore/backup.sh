#!/usr/bin/env bash

function main(){
    source <(curl -sS https://raw.githubusercontent.com/khangtictoc/Productive-Workspace-Set-Up/refs/heads/main/linux/utility/library/bash/ansi_color.sh)
    init-ansicolor

    current_time=$(date +"%Y.%m.%d-%H.%M.%S")
    cluster_name="$1"
    backup_file="$cluster_name-$current_time"

    echo "[INFO] Start backup ..."
    velero create backup  --include-cluster-scoped-resources="*" --include-namespaces="*" $backup_file
    echo "${GREEN}[SUCCESS] Backup Completed!${NC}"
}

main "$@"