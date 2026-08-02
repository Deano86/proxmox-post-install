#!/usr/bin/env bash
# Guarded scheduled update worker for Proxmox VE.
# Copyright (c) 2026 Deano86
# SPDX-License-Identifier: MIT
set -Eeuo pipefail

readonly CONFIG="/etc/default/proxmox-auto-update"
readonly LOG_FILE="/var/log/proxmox-auto-update.log"
readonly LOCK_FILE="/run/lock/proxmox-auto-update.lock"
MODE="check"
# shellcheck source=/dev/null
[[ -r $CONFIG ]] && source "$CONFIG"

install -d -m 0755 "$(dirname "$LOCK_FILE")"
touch "$LOG_FILE"
chmod 0640 "$LOG_FILE"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    printf '%s Another update run is active; exiting.\n' "$(date --iso-8601=seconds)" >>"$LOG_FILE"
    exit 0
fi
exec >>"$LOG_FILE" 2>&1

log() { printf '%s %s\n' "$(date --iso-8601=seconds)" "$*"; }
trap 'log "FAILED at line $LINENO with exit code $?"' ERR

log "Starting Proxmox automated update worker in mode=$MODE"

root_free_kb="$(df -Pk / | awk 'NR == 2 {print $4}')"
if [[ ${root_free_kb:-0} -lt 4194304 ]]; then
    log "ABORT: less than 4 GiB is free on the root filesystem."
    exit 1
fi
if [[ -n $(dpkg --audit 2>&1) ]]; then
    log "ABORT: dpkg reports incomplete package operations."
    dpkg --audit || true
    exit 1
fi

apt-get update
apt-get check

case "$MODE" in
    check)
        log "Available dist-upgrade simulation follows."
        apt-get --simulate dist-upgrade
        ;;
    install)
        if [[ -f /etc/pve/corosync.conf ]] &&
            ! pvecm status 2>/dev/null | grep -Eq 'Quorate:[[:space:]]+Yes'; then
            log "ABORT: cluster configuration exists but quorum is unavailable."
            exit 1
        fi
        log "Installing updates with apt-get dist-upgrade; automatic reboot is disabled."
        DEBIAN_FRONTEND=noninteractive \
            apt-get -y -o Dpkg::Options::="--force-confold" dist-upgrade
        if [[ -e /var/run/reboot-required ]]; then
            log "NOTICE: updates completed and a reboot is required."
        else
            log "Updates completed; no reboot-required marker is present."
        fi
        ;;
    *)
        log "ABORT: unsupported MODE=$MODE"
        exit 64
        ;;
esac
log "Automated update worker finished successfully."