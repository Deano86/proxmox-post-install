# Changelog

## 0.3.1 — 2026-08-02

- Fixed startup on Debian and Proxmox by renaming the script's readonly `VERSION` variable to `SCRIPT_VERSION`.
- Prevented the collision with the `VERSION` field sourced from `/etc/os-release`.
- Updated self-update version detection to recognize the renamed field.


## 0.3.0 — 2026-08-02

- Added a validated, backup-first script self-update command.
- Added guarded automated update checks using a persistent systemd timer.
- Added opt-in weekly package installation with disk, dpkg, APT, and cluster-quorum checks.
- Added update locking, logging, log rotation, status display, and run-now controls.
- Kept automatic reboot disabled and made check-only mode the recommended default.
- Published the update worker as a separately reviewable script.
- Extended Bash syntax and ShellCheck validation to the update worker.


## 0.2.0 — 2026-08-02

- Added interactive host health checks.
- Added permission-restricted diagnostic report export.
- Added dry-run mode for interactive mutations.
- Added safe PVE 9 legacy-to-deb822 repository migration.
- Added persistent repository backup manifests.
- Added validated interactive repository restoration.
- Added prominent Deano86 project branding.
- Retained targeted subscription-popup patching and APT persistence.

## 0.1.0 — 2026-08-02

- Initial interactive PVE 8/9 post-install utility.
- Added PVE and Ceph repository configuration with rollback.
- Added cluster-aware HA management.
- Embedded the verified no-subscription popup patch.
