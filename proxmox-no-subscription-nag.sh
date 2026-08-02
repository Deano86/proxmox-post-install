#!/usr/bin/env bash
# Targeted Proxmox VE subscription-popup patcher.
# Copyright (c) 2026 Deano86
# SPDX-License-Identifier: MIT
set -Eeuo pipefail
readonly TARGET="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
readonly BACKUP_DIR="/var/backups/proxmox-no-subscription-nag"
say() { printf '[proxmox-no-subscription-nag] %s\n' "$*"; }
die() { say "ERROR: $*" >&2; exit 1; }
is_patched() { grep -Pzq "void\\(\\{\\s*title:\\s*gettext\\('No valid subscription'\\)," "$TARGET"; }
is_unpatched() { grep -Pzq "Ext\\.Msg\\.show\\(\\{\\s*title:\\s*gettext\\('No valid subscription'\\)," "$TARGET"; }
patch_target() {
    [[ -f $TARGET ]] || die "Target not found: $TARGET"
    if is_patched; then say "Already patched: $TARGET"; return 0; fi
    is_unpatched || die "Expected popup code absent; refusing a broad replacement."
    local version stamp safe_version backup
    version="$(dpkg-query -W -f='${Version}' proxmox-widget-toolkit 2>/dev/null || printf unknown)"
    stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    safe_version="${version//[^a-zA-Z0-9._+~-]/_}"
    backup="${BACKUP_DIR}/proxmoxlib.js.${safe_version}.${stamp}"
    install -d -m 0750 "$BACKUP_DIR"
    cp -a -- "$TARGET" "$backup"
    say "Created backup: $backup"
    sed -Ezi "s/Ext\\.Msg\\.show\\(\\{([[:space:]]*title:[[:space:]]*gettext\\('No valid subscription'\\),)/void({\\1/" "$TARGET"
    if ! is_patched; then cp -a -- "$backup" "$TARGET"; die "Verification failed; backup restored."; fi
    systemctl is-active --quiet pveproxy.service && systemctl restart pveproxy.service
    say "SUCCESS: patch applied and verified."
}
show_status() {
    [[ -f $TARGET ]] || die "Target not found: $TARGET"
    if is_patched; then say "Status: PATCHED"
    elif is_unpatched; then say "Status: NOT PATCHED"
    else say "Status: UNKNOWN"; return 2; fi
    if [[ -f /etc/apt/apt.conf.d/99-proxmox-no-subscription-nag ]]; then
        say "APT hook: INSTALLED"
    else
        say "APT hook: NOT INSTALLED"
    fi
}
case "${1:-patch}" in
    patch) patch_target ;;
    status) show_status ;;
    *) printf 'Usage: %s {patch|status}\n' "$0" >&2; exit 64 ;;
esac