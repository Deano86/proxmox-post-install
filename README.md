# Deano86's Proxmox Post Install

An interactive, conservative post-install utility for Proxmox VE 8
(Bookworm) and Proxmox VE 9 (Trixie).

This project is derived from ideas in tteck's archived
[`misc/post-pve-install.sh`](https://github.com/tteck/Proxmox/blob/main/misc/post-pve-install.sh)
and is distributed under the MIT License with attribution preserved.

## Features

- Read-only configuration audit and host health checks.
- Dry-run menu that previews changes without writing.
- Validated self-update with version display and a timestamped backup.
- Guarded automated update checks using a persistent systemd timer.
- Optional scheduled package installation using `apt-get dist-upgrade`.
- PVE 9 legacy-to-deb822 repository migration with APT validation.
- Restorable repository backups with path-validated manifests.
- Mode-0600 diagnostic report export with a sharing warning.
- Runtime PVE version, Debian codename, and architecture detection.
- PVE 8 legacy `.list` and PVE 9 deb822 `.sources` support.
- Repository backups and automatic rollback when `apt-get update` fails.
- Conservative PVE enterprise/no-subscription configuration.
- Optional Ceph repository configuration with an explicit release choice.
- Targeted, self-verifying subscription-popup patch with an APT upgrade hook.
- Timestamped popup and repository backups.
- Cluster protection before disabling HA or Corosync.
- Interactive updates and reboot only after explicit confirmation.

> [!IMPORTANT]
> The no-subscription repository receives less validation than the enterprise
> repository and is not recommended by Proxmox for production use. The popup
> patch only changes a web-interface notification; it does not provide a
> subscription, support entitlement, or enterprise repository access.

## Install

Download and inspect the script before running it as root:

```bash
wget https://raw.githubusercontent.com/Deano86/proxmox-post-install/main/proxmox-post-install.sh
bash -n proxmox-post-install.sh
chmod +x proxmox-post-install.sh
sudo ./proxmox-post-install.sh
```

Avoid piping a remote script directly into a root shell. Saving it first lets
you inspect and syntax-check exactly what will run.

## Useful commands

```bash
# Interactive menu
sudo ./proxmox-post-install.sh

# Preview interactive changes without writing
sudo ./proxmox-post-install.sh --dry-run

# Configuration audit
sudo ./proxmox-post-install.sh --audit

# Host health checks
sudo ./proxmox-post-install.sh --health

# Create /root/proxmox-diagnostic-*.txt with mode 0600
sudo ./proxmox-post-install.sh --report

# Validate, back up, and replace this script from GitHub
sudo ./proxmox-post-install.sh --self-update

# Show the automated-update timer and its recent log
sudo ./proxmox-post-install.sh --update-status
```

The diagnostic report intentionally excludes guest configuration files,
subscription keys, and journal logs. It includes interface IP addresses, so
review it before sharing.

## Automated host updates

Open **Automated host updates** from the interactive menu. Available presets
are:

| Preset | Schedule | Behaviour |
|---|---|---|
| Daily check | Every day at 06:00 | Refreshes APT metadata and simulates `dist-upgrade` |
| Weekly check | Sunday at 04:00 | Refreshes APT metadata and simulates `dist-upgrade` |
| Weekly install | Sunday at 04:00 | Installs with guarded, noninteractive `dist-upgrade` |

Check-only mode is recommended. Install mode is deliberately opt-in because
unattended hypervisor changes carry operational risk. The worker:

- prevents overlapping runs with `flock`;
- requires at least 4 GiB free on the root filesystem;
- blocks on incomplete dpkg operations or failed APT validation;
- blocks clustered installs when quorum is unavailable;
- preserves locally modified package configuration files;
- logs to `/var/log/proxmox-auto-update.log`; and
- never reboots the host automatically.

The installed timer is persistent and uses a 30-minute randomized delay.
Configuration is stored in `/etc/default/proxmox-auto-update`. Use the menu to
run the configured worker immediately, inspect status, change the preset, or
remove it. Existing scheduler files are backed up below
`/var/backups/proxmox-post-install/`.

The standalone worker source is also published as
[`proxmox-auto-update.sh`](proxmox-auto-update.sh) for review. Normally, let
the main interactive script install it together with its systemd unit, timer,
configuration, and log rotation policy.

## Self-update safety

Self-update downloads a fresh copy from this repository, runs `bash -n`,
checks its declared version, asks for confirmation, and backs up the running
script before replacement. It does not automatically execute the new version;
rerun the command after updating.

## Safety model

- Repository changes are scoped to entries selected in the interactive menu.
- Every changed repository file is copied to
  `/var/backups/proxmox-post-install/` with a restoration manifest.
- Restore accepts only generated manifest paths below `/etc/apt/`, takes a
  fresh safety backup, and validates the result with APT.
- `apt-get update` validates repository changes immediately.
- Failed validation triggers an automatic rollback.
- Unknown PVE/Debian mappings are blocked from repository modification.
- HA disablement is blocked when `/etc/pve/corosync.conf` exists.
- The popup patch refuses to run if its exact expected code is absent.
- Package upgrades call a dedicated idempotent patch command rather than an
  inline `sed` expression embedded in APT configuration.
- Scheduled installation uses `dist-upgrade`, never plain `apt upgrade`.

## Supported mappings

| Proxmox VE | Debian | Repository format |
|---|---|---|
| 8.x | Bookworm | legacy `.list` |
| 9.x | Trixie | deb822 `.sources` |

## Attribution

Based on the original MIT-licensed Proxmox helper scripts by tteck. This is an
independent derivative and is not affiliated with or endorsed by Proxmox
Server Solutions GmbH, tteck, or the Community Scripts project.

## License

MIT
