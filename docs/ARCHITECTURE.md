# EZpenguin Architecture

## Overview

EZpenguin is a **Debian-minimal derivative** built with a fully scripted,
Docker-based pipeline. Every artifact is produced inside a container,
ensuring bit-for-bit reproducibility regardless of the host OS.

```
┌─────────────────────────────────────────────────────────────┐
│  HOST (macOS / Linux / CI)                                  │
│                                                             │
│  build/build.sh ──► docker run debian:bookworm-slim         │
│                         │                                   │
│                         ▼                                   │
│              1. debootstrap → base rootfs                   │
│                 (arm64: foreign 2-stage under qemu-user)    │
│              2. chroot   → install packages (config/)       │
│              3. overlay  → copy rootfs-overlay/             │
│              4. cleanup  → strip caches, logs, machine-id   │
│                         │                                   │
│                         ▼                                   │
│              5. TESTS   → tests/run-tests.sh (in chroot)    │
│                         │                                   │
│                         ▼                                   │
│              6. PACKAGE → rootfs tarball / IMG (build/image.sh)│
│                         → live ISO (build/iso.sh)           │
│                         │                                   │
│                         ▼                                   │
│              7. VERIFY  → QEMU boot tests (BIOS+UEFI+ISO)   │
│                         → interactive wizard smoke test     │
└─────────────────────────────────────────────────────────────┘
```

## Layers

### 1. Base layer — Debian
- **Suite:** `bookworm` (Debian 12, current stable)
- **Variant:** `minbase` via debootstrap, then curated package set
- Rationale: Debian stability + massive package universe; same foundation
  DietPi proves works across x86 and ARM.

### 2. EZpenguin layer
Everything that makes it *EZpenguin* lives in `rootfs-overlay/` and
`scripts/`:

| Path | Purpose |
|---|---|
| `/etc/ezpenguin/` | Distro identity, config, version |
| `/usr/local/bin/ez-*` | User-facing CLI tools |
| `/etc/apt/sources.list.d/` | Repo pinning (Debian + EZpenguin) |
| `ezpenguin-firstboot.service` | First-boot wizard (systemd) |
| `ezpenguin-installer` | Bare-metal installer frontend |

### 3. Build pipeline
- `build/build.sh` — orchestrator; single entry point
- `build/rootfs.sh` — creates the rootfs inside Docker (native or foreign
  arm64 debootstrap under qemu-user-static)
- `build/image.sh` — flashable disk image: amd64 = GPT BIOS-boot + ESP +
  root with GRUB for BIOS **and** UEFI; arm64 = GPT ESP + root, arm64-efi
  GRUB. Static UUID grub.cfg (deterministic, no build-time device paths)
- `build/iso.sh` — hybrid live ISO: squashfs live root (live-boot),
  grub-mkrescue layout, El Torito BIOS + UEFI records, size-budgeted
- `build/Dockerfile` — pinned build environment

### 3a. Live ISO design
```
ISO (hybrid, BIOS El Torito + UEFI El Torito + isohybrid MBR)
├── /boot/vmlinuz-*, /boot/initrd.img-*   (live-boot-enabled initramfs)
├── /boot/grub/grub.cfg                   (boot=live, serial console)
└── /live/filesystem.squashfs             (xz-compressed full rootfs)
```
On boot, live-boot scans devices, mounts the squashfs as the root
(overlayfs), systemd starts, and the wizard detects `boot=live` on the
kernel command line to offer disk installation via `ez-install`.

### 3b. Disk layout (amd64)
```
GPT: p1 1M   ef02 BIOS-boot   (GRUB i386-pc core)
     p2 260M ef00 ESP         (FAT32, EFI/BOOT/BOOTX64.EFI)
     p3 rest 8300 root        (ext4, LABEL=EZP_ROOT)
```
arm64 drops p1 (UEFI-only: ESP + root).

All steps are **idempotent** and fail fast. Exit code != 0 stops the line.

### 4. QA layer
Tests run *inside* the built rootfs (via chroot) before any artifact is
packaged. A build that fails tests produces no output. See
[TESTING.md](TESTING.md).

## Design principles

1. **Reproducible** — same commit → same output. No manual steps.
2. **Minimal** — nothing in the base that isn't required or explicitly chosen.
3. **Tested** — untested = broken. Every build runs the full QA suite.
4. **Boring** — prefer proven Debian defaults over cleverness.
5. **Automated** — first-boot wizard, not install-time questions where avoidable.

## First-boot flow (DietPi-inspired)

```
power on → systemd → ezpenguin-firstboot.service
  ├─ detect hardware (board/PC/VM)
  ├─ expand root filesystem
  ├─ ask: locale, timezone, keyboard, hostname, user, password
  ├─ apt update && upgrade
  ├─ (optional) install software sets
  └─ reboot → ready
```

## Versioning

`MAJOR.MINOR.PATCH` — e.g. `1.0.0`. Tracked in
`config/ezpenguin-version` and stamped into `/etc/ezpenguin/version`
at build time. Artifacts embed the version in their filename.
