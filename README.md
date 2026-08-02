# Deano86's Proxmox Post Install

An interactive, conservative post-install utility for Proxmox VE 8
(Bookworm) and Proxmox VE 9 (Trixie).

This project is derived from ideas in tteck's archived
[`misc/post-pve-install.sh`](https://github.com/tteck/Proxmox/blob/main/misc/post-pve-install.sh)
and is distributed under the MIT License with attribution preserved.

## Features

- Read-only audit mode.
- Runtime PVE version, Debian codename, and architecture detection.
- PVE 8 legacy `.list` and PVE 9 deb822 `.sources` support.
- Repository backups and automatic rollback when `apt-get update` fails.
- Conservative PVE enterprise/no-subscription configuration.
- Optional Ceph repository configuration with an explicit release choice.
- Targeted, self-verifying subscription-popup patch with an APT upgrade hook.
- Timestamped popup and repository backups.
- Cluster protection before disabling HA or Corosync.
- Updates and reboot only after explicit confirmation.

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

## Read-only audit

```bash
sudo ./proxmox-post-install.sh --audit
```

## Safety model

- Repository changes are scoped to entries selected in the interactive menu.
- Every changed repository file is copied to
  `/var/backups/proxmox-post-install/`.
- `apt-get update` validates repository changes immediately.
- Failed validation triggers an automatic rollback.
- Unknown PVE/Debian mappings are blocked from repository modification.
- HA disablement is blocked when `/etc/pve/corosync.conf` exists.
- The popup patch refuses to run if its exact expected code is absent.
- Package upgrades call a dedicated idempotent patch command rather than an
  inline `sed` expression embedded in APT configuration.

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
