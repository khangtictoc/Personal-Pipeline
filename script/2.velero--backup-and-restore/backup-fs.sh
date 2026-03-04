#!/usr/bin/env bash

function main(){
    source <(curl -sS https://raw.githubusercontent.com/khangtictoc/Productive-Workspace-Set-Up/refs/heads/main/linux/utility/library/bash/ansi_color.sh)
    init-ansicolor

    current_time=$(date +"%Y.%m.%d-%H.%M.%S")
    cluster_name="$1"
    cluster_name_formatted=$(echo "$cluster_name" | tr '[:upper:]' '[:lower:]')
    backup_file="$cluster_name_formatted-$current_time"

    echo "[INFO] Start fully backup - ${YELLOW}Cluster: $cluster_name, Recorded at: $current_time ${NC} ..."
    velero create backup  --include-cluster-scoped-resources="*" --include-namespaces="*" $backup_file
    echo "${GREEN}[SUCCESS] Backup Completed!${NC}"

    echo "[INFO] Confirm your backups:"
    velero backup get | grep --color=always "$backup_file"

    echo "[INFO] Review your backup"
    velero backup describe $backup_file

    echo "[INFO] Monitoring restoring logs"
    velero backup logs $backup_file 
}

main "$@"