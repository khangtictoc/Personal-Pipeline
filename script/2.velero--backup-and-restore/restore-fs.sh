#!/usr/bin/env bash

function main(){
    source <(curl -sS https://raw.githubusercontent.com/khangtictoc/Productive-Workspace-Set-Up/refs/heads/main/linux/utility/library/bash/ansi_color.sh)
    init-ansicolor

    echo "[INFO] Start fully restore ..."
    restore_version="$1"

    # Check if restore already exists
    if velero restore get | awk '{print $1}' | grep -q "^${restore_version}$"; then
        echo "${YELLOW}[WARN] Restore '${restore_version}' already exists. Removing old restores${NC}"
        velero restore delete "$restore_version"
    else
        velero restore create "$restore_version" --from-backup "$restore_version" --wait
        echo "${GREEN}[SUCCESS] Restore Completed!${NC}"
    fi

    echo "[INFO] Confirm your restorations:"
    velero restore get | grep --color=always "$restore_version"

    echo "[INFO] Monitoring restoring logs"
    velero restore logs "$restore_version"
}

main "$@"
