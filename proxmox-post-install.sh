#!/usr/bin/env bash
# Modern interactive Proxmox VE post-install utility.
# Based on tteck/Proxmox misc/post-pve-install.sh.
# Copyright (c) 2021-2024 tteck
# Modifications copyright (c) 2026 Deano86
# SPDX-License-Identifier: MIT

set -Eeuo pipefail
shopt -s nullglob

readonly AUTHOR="Deano86"
readonly PROJECT_URL="https://github.com/Deano86/proxmox-post-install"
readonly APP_NAME="Deano86's Proxmox Post Install"
readonly BACKUP_ROOT="/var/backups/proxmox-post-install"
readonly NAG_TARGET="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
readonly NAG_COMMAND="/usr/local/sbin/proxmox-no-subscription-nag"
readonly NAG_HOOK="/etc/apt/apt.conf.d/99-proxmox-no-subscription-nag"

PVE_MAJOR=""
PVE_VERSION=""
CODENAME=""
ARCH=""
TX_DIR=""
declare -a TX_PATHS=()
declare -a TX_BACKUPS=()
declare -a TX_EXISTED=()

say() { printf '[proxmox-post-install] %s\n' "$*"; }
warn() { printf '[proxmox-post-install] WARNING: %s\n' "$*" >&2; }
die() { printf '[proxmox-post-install] ERROR: %s\n' "$*" >&2; exit 1; }
on_error() { warn "Command failed at line $1 with exit code $2."; }
trap 'on_error "$LINENO" "$?"' ERR

require_root() { [[ ${EUID} -eq 0 ]] || die "Run this script as root."; }
require_command() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }

detect_platform() {
    [[ -r /etc/os-release ]] || die "/etc/os-release is unavailable."
    # shellcheck disable=SC1091
    source /etc/os-release
    CODENAME="${VERSION_CODENAME:-}"
    ARCH="$(dpkg --print-architecture 2>/dev/null || true)"
    command -v pveversion >/dev/null 2>&1 || die "This is not a Proxmox VE host."
    PVE_VERSION="$(pveversion 2>/dev/null | sed -nE 's#^pve-manager/([0-9]+\.[0-9.]+).*#\1#p')"
    PVE_MAJOR="${PVE_VERSION%%.*}"
    [[ -n ${PVE_VERSION} && ${PVE_MAJOR} =~ ^(8|9)$ ]] ||
        die "Supported PVE majors are 8 and 9; detected: ${PVE_VERSION:-unknown}."
}

validate_repo_platform() {
    case "${PVE_MAJOR}:${CODENAME}" in
        8:bookworm | 9:trixie) return 0 ;;
        *) warn "Unsupported repository mapping: PVE $PVE_VERSION / $CODENAME."; return 1 ;;
    esac
}

menu() {
    local title="$1" prompt="$2"
    shift 2
    whiptail --backtitle "$APP_NAME" --title "$title" \
        --menu "$prompt" 22 78 12 "$@" 3>&1 1>&2 2>&3
}
confirm() { whiptail --backtitle "$APP_NAME" --title "$1" --yesno "$2" 14 78; }
message() { whiptail --backtitle "$APP_NAME" --title "$1" --msgbox "$2" 20 78; }

begin_transaction() {
    TX_DIR="${BACKUP_ROOT}/$1-$(date -u +%Y%m%dT%H%M%SZ)"
    install -d -m 0750 "$TX_DIR"
    TX_PATHS=()
    TX_BACKUPS=()
    TX_EXISTED=()
}

backup_path() {
    local path="$1" index
    for index in "${!TX_PATHS[@]}"; do
        [[ ${TX_PATHS[$index]} == "$path" ]] && return 0
    done
    index="${#TX_PATHS[@]}"
    TX_PATHS+=("$path")
    TX_BACKUPS+=("$TX_DIR/item-$index")
    if [[ -e $path ]]; then
        cp -a -- "$path" "${TX_BACKUPS[$index]}"
        TX_EXISTED+=(1)
    else
        TX_EXISTED+=(0)
    fi
}

rollback_transaction() {
    local index path
    warn "Rolling back changes from $TX_DIR."
    for index in "${!TX_PATHS[@]}"; do
        path="${TX_PATHS[$index]}"
        rm -f -- "$path"
        if [[ ${TX_EXISTED[$index]} -eq 1 ]]; then
            install -d -m 0755 "$(dirname -- "$path")"
            cp -a -- "${TX_BACKUPS[$index]}" "$path"
        fi
    done
}

source_files() {
    local files=(/etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources)
    local file
    for file in "${files[@]}"; do [[ -f $file ]] && printf '%s\n' "$file"; done
}

show_audit() {
    local toolkit nag_status="UNKNOWN" hook_status cluster_status
    toolkit="$(dpkg-query -W -f='${Version}' proxmox-widget-toolkit 2>/dev/null || printf 'not installed')"
    if [[ -f $NAG_TARGET ]]; then
        if grep -Pzq "void\\(\\{\\s*title:\\s*gettext\\('No valid subscription'\\)," "$NAG_TARGET"; then
            nag_status="PATCHED"
        elif grep -Pzq "Ext\\.Msg\\.show\\(\\{\\s*title:\\s*gettext\\('No valid subscription'\\)," "$NAG_TARGET"; then
            nag_status="NOT PATCHED"
        fi
    fi
    printf '\n=== %s ===\nProject: %s\n\n' "$APP_NAME" "$PROJECT_URL"
    printf '=== Platform ===\nPVE: %s\nDebian: %s\nArchitecture: %s\nToolkit: %s\n' \
        "$PVE_VERSION" "$CODENAME" "$ARCH" "$toolkit"
    printf '\n=== APT sources ===\n'
    while IFS= read -r file; do
        printf '\n[%s]\n' "$file"
        grep -E '^(deb |Types:|URIs:|Suites:|Components:|Enabled:|#.*deb )' "$file" || true
    done < <(source_files)
    if [[ -f $NAG_HOOK ]]; then hook_status="INSTALLED"; else hook_status="NOT INSTALLED"; fi
    if [[ -f /etc/pve/corosync.conf ]]; then cluster_status="PRESENT"; else cluster_status="ABSENT"; fi
    printf '\n=== Popup patch ===\nStatus: %s\nHook: %s\n' "$nag_status" "$hook_status"
    printf '\n=== Cluster and HA ===\nCluster config: %s\npve-ha-lrm: %s\npve-ha-crm: %s\ncorosync: %s\n' \
        "$cluster_status" \
        "$(systemctl is-active pve-ha-lrm 2>/dev/null || true)" \
        "$(systemctl is-active pve-ha-crm 2>/dev/null || true)" \
        "$(systemctl is-active corosync 2>/dev/null || true)"
}

disable_deb822_stanzas() {
    local file="$1" pattern="$2" temporary
    temporary="$(mktemp)"
    awk -v pattern="$pattern" '
        BEGIN { RS=""; ORS="\n\n" }
        {
            if ($0 ~ pattern) {
                if ($0 ~ /(^|\n)Enabled:/) gsub(/\nEnabled:[^\n]*/, "\nEnabled: false")
                else $0 = $0 "\nEnabled: false"
            }
            print
        }
    ' "$file" >"$temporary"
    cat "$temporary" >"$file"
    rm -f -- "$temporary"
}

disable_pve_enterprise() {
    local file
    while IFS= read -r file; do
        grep -q 'pve-enterprise' "$file" || continue
        backup_path "$file"
        case "$file" in
            *.sources) disable_deb822_stanzas "$file" 'Components:[^\n]*pve-enterprise' ;;
            *) sed -Ei '/^[[:space:]]*deb .*pve-enterprise/s/^/# disabled by proxmox-post-install: /' "$file" ;;
        esac
        say "Disabled PVE enterprise entry in $file"
    done < <(source_files)
}

disable_ceph_enterprise() {
    local file
    while IFS= read -r file; do
        grep -qE 'enterprise\.proxmox\.com/debian/ceph-' "$file" || continue
        backup_path "$file"
        case "$file" in
            *.sources) disable_deb822_stanzas "$file" 'enterprise\.proxmox\.com/debian/ceph-' ;;
            *) sed -Ei '/^[[:space:]]*deb .*enterprise\.proxmox\.com\/debian\/ceph-/s/^/# disabled by proxmox-post-install: /' "$file" ;;
        esac
        say "Disabled Ceph enterprise entry in $file"
    done < <(source_files)
}

active_component_exists() {
    local component="$1" file
    while IFS= read -r file; do
        case "$file" in
            *.sources)
                awk -v component="$component" '
                    BEGIN { RS="" }
                    $0 ~ "Components:[^\\n]*" component &&
                    $0 !~ /(^|\n)Enabled:[[:space:]]*false/ { found=1 }
                    END { exit(found ? 0 : 1) }
                ' "$file" && return 0
                ;;
            *) grep -Eq "^[[:space:]]*deb .*$component" "$file" && return 0 ;;
        esac
    done < <(source_files)
    return 1
}

write_pve_no_subscription() {
    local target
    if [[ $PVE_MAJOR == 9 ]]; then
        target="/etc/apt/sources.list.d/pve-no-subscription.sources"
        backup_path "$target"
        cat >"$target" <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: $CODENAME
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
    else
        target="/etc/apt/sources.list.d/pve-no-subscription.list"
        backup_path "$target"
        printf 'deb http://download.proxmox.com/debian/pve %s pve-no-subscription\n' "$CODENAME" >"$target"
    fi
    chmod 0644 "$target"
    say "Configured $target"
}

validate_apt_or_rollback() {
    say "Validating with apt-get update..."
    if apt-get update; then
        say "Backup retained at $TX_DIR"
        return 0
    fi
    rollback_transaction
    apt-get update || warn "APT still reports an error after rollback."
    return 1
}

configure_pve_repositories() {
    validate_repo_platform || { message "Unsupported mapping" "Repository changes were blocked."; return; }
    begin_transaction "pve-repositories"
    if confirm "Enterprise repository" "Disable PVE enterprise entries?\n\nChoose No with a valid subscription."; then
        disable_pve_enterprise
    fi
    if active_component_exists "pve-no-subscription"; then
        say "PVE no-subscription is already active."
    elif confirm "No-subscription repository" \
        "Add PVE no-subscription for $CODENAME?\n\nEnterprise is recommended for production."; then
        write_pve_no_subscription
    fi
    [[ ${#TX_PATHS[@]} -gt 0 ]] || { say "No changes requested."; return; }
    validate_apt_or_rollback || message "Rollback" "APT validation failed; changes were rolled back."
}

choose_ceph_release() {
    if [[ $PVE_MAJOR == 9 ]]; then
        menu "Ceph release" "Only add this when the node uses Ceph packages." \
            none "Do not add" squid "Squid (PVE 9 default)" reef "Reef" quincy "Quincy"
    else
        menu "Ceph release" "Only add this when the node uses Ceph packages." \
            none "Do not add" reef "Reef (PVE 8 default)" quincy "Quincy" squid "Squid"
    fi
}

ceph_no_subscription_exists() {
    local release="$1" file
    while IFS= read -r file; do
        case "$file" in
            *.sources)
                awk -v release="$release" '
                    BEGIN { RS="" }
                    $0 ~ "URIs:[^\\n]*download.proxmox.com/debian/ceph-" release &&
                    $0 ~ /Components:[^\n]*no-subscription/ &&
                    $0 !~ /(^|\n)Enabled:[[:space:]]*false/ { found=1 }
                    END { exit(found ? 0 : 1) }
                ' "$file" && return 0
                ;;
            *) grep -Eq "^[[:space:]]*deb .*download\.proxmox\.com/debian/ceph-$release .*no-subscription" "$file" && return 0 ;;
        esac
    done < <(source_files)
    return 1
}

write_ceph_no_subscription() {
    local release="$1" target
    if [[ $PVE_MAJOR == 9 ]]; then
        target="/etc/apt/sources.list.d/ceph-$release-no-subscription.sources"
        backup_path "$target"
        cat >"$target" <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/ceph-$release
Suites: $CODENAME
Components: no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
    else
        target="/etc/apt/sources.list.d/ceph-$release-no-subscription.list"
        backup_path "$target"
        printf 'deb http://download.proxmox.com/debian/ceph-%s %s no-subscription\n' "$release" "$CODENAME" >"$target"
    fi
    chmod 0644 "$target"
    say "Configured $target"
}

configure_ceph_repositories() {
    local release
    validate_repo_platform || { message "Unsupported mapping" "Ceph changes were blocked."; return; }
    begin_transaction "ceph-repositories"
    if confirm "Ceph enterprise" "Disable Ceph enterprise entries?\n\nChoose No with a valid subscription."; then
        disable_ceph_enterprise
    fi
    release="$(choose_ceph_release || printf none)"
    if [[ $release != none ]]; then
        if ceph_no_subscription_exists "$release"; then
            say "Ceph $release no-subscription is already active."
        else
            write_ceph_no_subscription "$release"
        fi
    fi
    [[ ${#TX_PATHS[@]} -gt 0 ]] || { say "No changes requested."; return; }
    validate_apt_or_rollback || message "Rollback" "APT validation failed; changes were rolled back."
}

write_nag_command() {
    cat >"$NAG_COMMAND" <<'NAG_SCRIPT'
#!/usr/bin/env bash
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
NAG_SCRIPT
    chmod 0755 "$NAG_COMMAND"
}

install_nag_patch() {
    local backup_dir hook
    backup_dir="$BACKUP_ROOT/legacy-nag-$(date -u +%Y%m%dT%H%M%SZ)"
    install -d -m 0750 "$backup_dir"
    [[ -f $NAG_COMMAND ]] && cp -a -- "$NAG_COMMAND" "$backup_dir/"
    for hook in /etc/apt/apt.conf.d/no-nag-script /etc/apt/apt.conf.d/99-pve-nag-fix "$NAG_HOOK"; do
        if [[ -f $hook ]]; then
            cp -a -- "$hook" "$backup_dir/"
            rm -f -- "$hook"
            say "Disabled previous hook: $hook"
        fi
    done
    while IFS= read -r hook; do
        cp -a -- "$hook" "$backup_dir/"
        rm -f -- "$hook"
        say "Disabled additional legacy hook: $hook"
    done < <(grep -RlE 'proxmoxlib\.js|fix-proxmox-subscription|pve-remove-nag' /etc/apt/apt.conf.d 2>/dev/null || true)
    write_nag_command
    printf 'DPkg::Post-Invoke { "/usr/local/sbin/proxmox-no-subscription-nag patch || echo '\''WARNING: Proxmox popup patch failed.'\'' >&2"; };\n' >"$NAG_HOOK"
    chmod 0644 "$NAG_HOOK"
    "$NAG_COMMAND" patch
    "$NAG_COMMAND" status
    say "Legacy hook backups: $backup_dir"
}

remove_nag_patch() {
    confirm "Restore dialog" "Remove the hook and reinstall the official toolkit file?" || return 0
    rm -f -- "$NAG_HOOK" "$NAG_COMMAND"
    apt-get install --reinstall proxmox-widget-toolkit
    systemctl restart pveproxy.service
    if dpkg -V proxmox-widget-toolkit 2>/dev/null | grep -q '/proxmoxlib\.js$'; then
        warn "proxmoxlib.js still differs from the package."
    else
        say "Official proxmoxlib.js restored."
    fi
}

manage_ha() {
    local choice
    choice="$(menu "High availability" "Current state: $(systemctl is-active pve-ha-lrm 2>/dev/null || true)" \
        leave "No changes" enable "Enable HA" disable "Disable on a standalone node" || printf leave)"
    case "$choice" in
        enable)
            systemctl enable --now pve-ha-lrm pve-ha-crm
            if [[ -f /etc/pve/corosync.conf ]]; then
                systemctl enable --now corosync
            fi
            ;;
        disable)
            if [[ -f /etc/pve/corosync.conf ]]; then
                message "Cluster protection" "Corosync configuration exists; HA disablement was blocked."
                return
            fi
            if confirm "Standalone node" "Disable HA and Corosync services?"; then
                systemctl disable --now pve-ha-lrm pve-ha-crm 2>/dev/null || true
                systemctl disable --now corosync 2>/dev/null || true
            fi
            ;;
    esac
}

update_system() {
    confirm "System update" "Run apt-get update and interactive dist-upgrade?" || return 0
    apt-get update
    apt-get dist-upgrade
}
reboot_host() {
    if confirm "Reboot" "Reboot this host now?"; then
        reboot
    fi
}

interactive_main() {
    local choice
    require_command whiptail
    while true; do
        choice="$(menu "PVE $PVE_VERSION ($CODENAME)" "Choose an operation." \
            audit "Read-only audit" pve-repos "Configure PVE repositories" \
            ceph-repos "Configure Ceph repositories" nag-install "Install/update popup patch" \
            nag-remove "Remove patch and restore toolkit" ha "Manage HA services" \
            update "Interactive system update" reboot "Reboot host" exit "Exit" || printf exit)"
        case "$choice" in
            audit) show_audit; read -r -p "Press Enter to return..." _ ;;
            pve-repos) configure_pve_repositories ;;
            ceph-repos) configure_ceph_repositories ;;
            nag-install)
                if confirm "Popup patch" "Install the targeted patch and APT hook?\n\nThis changes only the UI notification."; then
                    install_nag_patch
                fi
                ;;
            nag-remove) remove_nag_patch ;;
            ha) manage_ha ;;
            update) update_system ;;
            reboot) reboot_host ;;
            exit) break ;;
        esac
    done
}

usage() {
    cat <<'EOF'
Deano86's Proxmox Post Install
Project: https://github.com/Deano86/proxmox-post-install

Usage: proxmox-post-install.sh [--interactive|--audit|--help]
EOF
}

main() {
    if [[ ${1:-} == "--help" || ${1:-} == "-h" ]]; then
        usage
        return 0
    fi
    require_root
    detect_platform
    case "${1:---interactive}" in
        --interactive) interactive_main ;;
        --audit) show_audit ;;
        --help|-h) usage ;;
        *) usage >&2; exit 64 ;;
    esac
}
main "$@"
