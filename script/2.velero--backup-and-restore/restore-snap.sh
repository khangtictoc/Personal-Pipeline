#!/usr/bin/env bash

function main(){
    source <(curl -sS https://raw.githubusercontent.com/khangtictoc/Productive-Workspace-Set-Up/refs/heads/main/linux/utility/library/bash/ansi_color.sh)
    init-ansicolor

    echo "[INFO] Start restore ..."
    restore_version="$1"
    velero restore create $restore_version --from-backup $restore_version
    echo "${GREEN}[SUCCESS] Restore Completed!${NC}"
}

main "$@"