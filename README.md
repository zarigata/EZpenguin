# EZpenguin 🐧

**A tiny Debian-based Linux distribution that boots anywhere and installs itself in minutes.**

```text
      ███████╗███████╗████████╗██████╗
      ██╔════╝██╔════╝╚══██╔══╝██╔══██╗
      █████╗  █████╗     ██║   ██████╔╝
      ██╔══╝  ██╔══╝     ██║   ██╔══██╗
      ███████╗███████╗   ██║   ██╗  ██╗
      ╚══════╝╚══════╝   ╚═╝   ╚═╝  ╚═╝
              EZ  •  PENGUIN
```

[![Type](https://img.shields.io/badge/type-Linux%20distribution-blue)](https://github.com/zarigata/EZpenguin)
[![Base](https://img.shields.io/badge/base-Debian%20bookworm-red)](https://www.debian.org)
[![Version](https://img.shields.io/badge/version-0.2.0-green)](docs/CHANGELOG.md)
[![License](https://img.shields.io/badge/license-GPL--3.0-lightgrey)](LICENSE)
[![Tests](https://img.shields.io/badge/QA-100%25%20automated-brightgreen)](docs/TESTING.md)

---

## What is it?

EZpenguin is a minimal, appliance-style Linux OS built on **Debian bookworm**:

- **~690 MB installed / ~320 MB image download** — runs on old/low-spec hardware
- **Boots on any PC** — hybrid BIOS + UEFI, flash-and-go (no installer needed)
- **Live ISO installer** — boot from USB, install to disk with a few keypresses
- **Self-configuring** — first-boot wizard: locale, timezone, keyboard, hostname,
  user, optional SSH, updates — then it reboots ready to use
- **ARM64 support** — same pipeline cross-builds aarch64 images (Pi 4/5 class)
- **100% reproducible** — Docker-based build; identical artifacts every run
- **Continuously verified** — every build runs ~130 automated checks plus full
  QEMU boot tests (BIOS + UEFI + live ISO + interactive wizard walkthrough)

Inspired by [DietPi](https://dietpi.com)'s install experience; built for standard
PCs, VMs, and ARM boards.

## Test-drive it (60 seconds, any OS with Docker)

```bash
docker run --rm -it --privileged \
    -v "$PWD/artifacts:/art" \
    debian:bookworm-slim bash -c "
      apt-get update && apt-get install -y qemu-system-x86 xz-utils &&
      xz -d -c /art/ezpenguin-0.2.0-amd64.img.xz > /tmp/ezp.img &&
      qemu-system-x86_64 -m 1024 -drive file=/tmp/ezp.img,format=raw,if=virtio \
        -netdev user,id=n0 -device virtio-net-pci,netdev=n0 -nographic"
```

Press `Ctrl+A` then `X` to quit QEMU. On first boot the wizard walks you through
configuration in under a minute.

Or build everything from scratch and watch it test itself:

```bash
./build/build.sh all        # rootfs → 130 tests → image → QEMU boot tests → ISO
```

## Get it onto a PC

### Option 1 — Flash the image (fastest)

```bash
xz -d ezpenguin-0.2.0-amd64.img.xz
sudo dd if=ezpenguin-0.2.0-amd64.img of=/dev/sdX bs=4M status=progress   # USB
```

Boot from USB (BIOS or UEFI). The root partition auto-expands to fill the disk
on first boot.

### Option 2 — Live ISO installer

Write `ezpenguin-0.2.0-amd64.iso` to USB (`dd` or Rufus/Etcher), boot it, and the
first-boot wizard offers **Install EZpenguin to a disk** — pick a disk, confirm,
reboot into your system. The installed system then runs the normal first-boot
wizard.

### Option 3 — From any running Linux (DietPi-style)

```bash
sudo ./installer/install.sh /dev/sdX ezpenguin-0.2.0-amd64-rootfs.tar.xz
```

## Ships with

| Tool | Purpose |
|---|---|
| `ez-firstboot` | First-boot wizard (runs automatically on tty1) |
| `ez-install` | Live-ISO / runtime installer (BIOS+UEFI target install) |
| `ez-doctor` | System health check — memory, disk, services, network, security |
| `ez-net` | Network status & diagnostics in one command |
| `ez-info` | System summary |
| `ez-update` | Update packages |
| `ez-config` | Re-run configuration |

All tools are plain, auditable bash — no magic.

## Platform support

| Platform | Status |
|---|---|
| x86-64 BIOS (SeaBIOS) | ✅ boot-tested every build |
| x86-64 UEFI (OVMF/edk2) | ✅ boot-tested every build |
| ARM64 / aarch64 (UEFI) | ✅ cross-built + boot-tested (QEMU virt) |
| VirtualBox / VMware / KVM / Hyper-V | ✅ (standard BIOS/UEFI) |
| Raspberry Pi 4/5 (ARM64) | 🧪 UEFI-boot Pi variants |

## Repository layout

```
EZpenguin/
├── build/            # build pipeline: rootfs → image → ISO (Docker-isolated)
├── config/           # distro config + package lists (single source of truth)
├── rootfs-overlay/   # files copied verbatim into the OS (tools, units, net)
├── installer/        # bare-metal installer (runs from any Linux)
├── tests/            # ~130-check QA suite + QEMU boot/ISO/wizard tests
├── docs/             # full documentation set
└── artifacts/        # build outputs (img.xz, rootfs.tar.xz, iso)
```

## Documentation

| Doc | Contents |
|---|---|
| [Architecture](docs/ARCHITECTURE.md) | How the distro and build system are designed |
| [Building](docs/BUILDING.md) | Build it yourself — all stages, amd64 + arm64 |
| [Installation](docs/INSTALLATION.md) | Install on PCs, VMs, ARM |
| [Testing](docs/TESTING.md) | QA strategy: static checks → QEMU boot tests |
| [Quality](docs/QUALITY.md) | Definition of done, size/security budgets |
| [Roadmap](docs/ROADMAP.md) | v0.2 → v1.0 plan |
| [Security](docs/SECURITY.md) | Hardening defaults & policy |
| [Contributing](docs/CONTRIBUTING.md) | How to help |
| [Changelog](docs/CHANGELOG.md) | Version history |

## Design principles

1. **Minimal but complete** — one meta-config (`config/`) drives everything.
2. **Verified, not trusted** — if it isn't boot-tested, it doesn't ship.
3. **Boring tech** — Debian base, systemd, GRUB, bash. No NIH.
4. **Reproducible** — one Docker command rebuilds the whole OS from zero.

## License

GPL-3.0 — see [LICENSE](LICENSE). Debian packages follow their own licenses.
