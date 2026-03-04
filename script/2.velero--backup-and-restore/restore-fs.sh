#!/usr/bin/env bash

function main(){
    source <(curl -sS https://raw.githubusercontent.com/khangtictoc/Productive-Workspace-Set-Up/refs/heads/main/linux/utility/library/bash/ansi_color.sh)
    init-ansicolor

    echo "[INFO] Start fully restore ..."
    restore_version="$1"
    velero restore create $restore_version --from-backup $restore_version --wait
    echo "${GREEN}[SUCCESS] Restore Completed!${NC}"

    echo "[INFO] Confirm your restorations:"
    velero restore get | grep --color=always "$restore_version"

    echo "[INFO] Review your restorations"
    velero restore describe $restore_version

    echo "[INFO] Monitoring restoring logs"
    velero restore logs $restore_version
}

main "$@"