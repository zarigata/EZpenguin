<div align="center">

```
        .--.
       |o_o |
       |:_/ |
      //   \ \
     (|     | )
    /"\_   _/`\
    \___)=(___/
```

# EZpenguin 🐧

**A tiny Debian-based Linux distribution that boots anywhere,
installs itself in minutes, and now installs IN PLACE with one line.**

[![Type](https://img.shields.io/badge/type-Linux%20distribution-blue)](https://github.com/zarigata/EZpenguin)
[![Base](https://img.shields.io/badge/base-Debian%20bookworm-red)](https://www.debian.org)
[![Version](https://img.shields.io/badge/version-0.4.1-green)](docs/CHANGELOG.md)
[![License](https://img.shields.io/badge/license-GPL--3.0-lightgrey)](LICENSE)
[![QA](https://img.shields.io/badge/QA-137%20automated%20checks-brightgreen)](docs/TESTING.md)
[![GitHub Pages](https://img.shields.io/badge/site-github%20pages-orange)](https://zarigata.github.io/EZpenguin/)

[Features](#-what-is-it) · [One-liner Install](#-one-liner-install) · [Test-drive](#%EF%B8%8F-test-drive-it-60-seconds) · [Software Catalog](#-software-catalog-61-stacks) · [Docs](#-documentation) · [Roadmap](#%EF%B8%8F-roadmap)

</div>

---

## 🚀 One-liner Install

Convert **any running Ubuntu/Debian system or container** into EZpenguin —
no ISO, no USB, no reboot media. Just like DietPi:

```bash
bash -c "$(curl -sSfL https://raw.githubusercontent.com/zarigata/EZpenguin/main/installer/online-installer.sh)"
```

The installer:

1. detects your environment (container vs bare metal) and architecture (amd64/arm64)
2. downloads the latest EZpenguin rootfs from [releases](https://github.com/zarigata/EZpenguin/releases)
3. **containers/VMs**: converts the running system in place and reboots (container restart = boot)
4. **bare metal**: partitions a target disk you pick, installs GRUB (BIOS+UEFI), reboots

Proven in CI-style testing: `ubuntu:24.04` Docker container → one-liner →
container restarts as EZpenguin with working `apt`, all `ez-*` tools, and the
first-boot wizard pending.

```bash
# see it yourself (60–90 seconds):
docker run -d --name ezp-demo ubuntu:24.04 sleep infinity
docker exec -it ezp-demo bash -c 'apt-get update -qq && apt-get install -y -qq curl xz-utils'
docker exec -it ezp-demo bash -c "$(curl -sSfL https://raw.githubusercontent.com/zarigata/EZpenguin/main/installer/online-installer.sh)"
docker restart ezp-demo        # ← the "reboot": boots into EZpenguin
docker exec ezp-demo ez-info   # it's a penguin now
```

## ✨ What is it?

EZpenguin is a minimal, appliance-style Linux OS built on **Debian bookworm**:

| | |
|---|---|
| 🪶 **~690 MB installed / ~320 MB download** | runs on old/low-spec hardware |
| 🔥 **Boots on any PC** | hybrid BIOS + UEFI, flash-and-go — no installer needed |
| 📀 **Live ISO installer** | boot from USB, install to disk with a few keypresses |
| ⚡ **One-liner in-place install** | convert running systems/containers, DietPi-style |
| 🧙 **Self-configuring** | interactive wizard **or** zero-touch headless mode |
| 📦 **Software catalog** | 61 curated stacks — docker, python, java, node, VPNs, desktops |
| 🔐 **DietPi-style global password** | one password for user+root, opt-in |
| 🦾 **ARM64 support** | same pipeline cross-builds aarch64 images |
| ♻️ **100% reproducible** | Docker-based build; identical artifacts every run |
| ✅ **Verified, not trusted** | 137 automated checks + QEMU boot tests on every build |

## ⏱️ Test-drive it (60 seconds, any OS with Docker)

```bash
docker run --rm -it --privileged \
    -v "$PWD/artifacts:/art" \
    debian:bookworm-slim bash -c "
      apt-get update && apt-get install -y qemu-system-x86 xz-utils &&
      xz -d -c /art/ezpenguin-0.4.1-amd64.img.xz > /tmp/ezp.img &&
      qemu-system-x86_64 -m 1024 -drive file=/tmp/ezp.img,format=raw,if=virtio \
        -netdev user,id=n0 -device virtio-net-pci,netdev=n0 -nographic"
```

Press `Ctrl+A` then `X` to quit QEMU. Or build everything from scratch and
watch it test itself:

```bash
./build/build.sh all    # rootfs → 137 tests → image → boot tests → ISO → wizard walkthrough
```

## 📦 Software Catalog (61 stacks)

```bash
sudo ez-software            # TUI: category menu → checklist → install
ez-software list            # browse all 61
sudo ez-software install docker python java nodejs
```

| Category | Highlights |
|---|---|
| 🖥️ servers | nginx, apache, caddy, lighttpd, mariadb, postgres, redis, docker, podman, samba, nfs, cockpit, syncthing, gitea(gogs), mosquitto |
| 👨‍💻 dev languages | python 3 + venv + pipx, node.js + npm, java 17 (OpenJDK), go, rust, php 8 + fpm, ruby, build-essential |
| 🌐 network/VPN | wireguard, openvpn, tailscale, mosh, nmap, tshark, tcpdump |
| 🔒 security | fail2ban, ufw, auditd, clamav, rkhunter, unattended-upgrades |
| 📊 monitoring/tools | btop, htop, tmux, byobu, mc, ncdu, neofetch, inxi, tldr, iperf3, smartmontools, lm-sensors |
| 🎨 desktops | XFCE, LXDE (one command each) |

Each entry has **post-install hooks**: services enabled, docker group membership,
php-fpm started, graphical target set.

## 🧙 First boot: interactive OR zero-touch

**Interactive** (wizard on tty1): locale, timezone, keymap, hostname, user,
SSH, updates — reboots ready to use.

**Headless** — drop `/boot/firstboot.conf` on the flashed disk:

```ini
EZ_LOCALE=en_US.UTF-8
EZ_TIMEZONE=Europe/Lisbon
EZ_HOSTNAME=mybox
EZ_USERNAME=penguin
EZ_PASSWORD=changeme
EZ_SSH_ENABLE=1        # ssh-first deployment, zero keystrokes
EZ_GLOBAL_PASSWORD=1   # DietPi-style: same password for root (opt-in)
```

Verified by automated tests: **80 s unattended setup, SSH auto-enabled,
VM reboots itself.**

## 🚢 Get it onto a machine

| Method | How | Best for |
|---|---|---|
| **One-liner** | `bash -c "$(curl -sSfL .../online-installer.sh)"` | converting running systems/containers |
| **Flash image** | `dd` the `.img.xz` to USB → boot | new PCs, fastest path |
| **Live ISO** | boot `.iso` → "Install EZpenguin to a disk" | classic installer UX |
| **DietPi-style script** | `sudo installer/install.sh /dev/sdX` | from any Linux |

Artifacts on [releases](https://github.com/zarigata/EZpenguin/releases):
amd64 `img.xz` (~320 MB) · `iso` (~250 MB) · `rootfs.tar.xz` (~161 MB) ·
arm64 `img.xz` (~280 MB).

## 🛠️ Ships with

`ez-firstboot` (wizard) · `ez-install` · `ez-software` (catalog) ·
`ez-config` (full settings tool) · `ez-backup` · `ez-doctor` (health check) ·
`ez-net` (diagnostics) · `ez-info` (fastfetch-style panel) · `ez-update`

All plain, auditable bash.

## 🏗️ Repository layout

```
EZpenguin/
├── build/            # build pipeline: rootfs → image → ISO (Docker-isolated)
├── config/           # distro config + package + software catalogs
├── rootfs-overlay/   # files copied verbatim into the OS (tools, units, net)
├── installer/        # one-liner online installer + bare-metal installer
├── tests/            # 137-check QA + QEMU boot/ISO/wizard/headless tests
├── docs/             # full documentation + GitHub Pages site
└── artifacts/        # build outputs (gitignored binaries)
```

## 📚 Documentation

| Doc | Contents |
|---|---|
| [Architecture](docs/ARCHITECTURE.md) | How the distro and build system are designed |
| [Building](docs/BUILDING.md) | Build it yourself — all stages, amd64 + arm64 |
| [Installation](docs/INSTALLATION.md) | Install on PCs, VMs, ARM, containers, headless |
| [Testing](docs/TESTING.md) | QA strategy: static checks → QEMU boot tests |
| [Quality](docs/QUALITY.md) | Definition of done, size/security budgets |
| [Roadmap](docs/ROADMAP.md) | v0.4 → v1.0 plan |
| [Security](docs/SECURITY.md) | Hardening defaults & policy |
| [Contributing](docs/CONTRIBUTING.md) | How to help |
| [Changelog](docs/CHANGELOG.md) | Version history |

## 🗺️ Roadmap

- [x] v0.1 foundation — build pipeline, BIOS+UEFI image, 106 checks
- [x] v0.2 installability — live ISO installer, ARM64, wizard automation
- [x] v0.3 DietPi-parity UX — catalog, headless, ez-config/ez-backup
- [x] v0.4 software & UX — 61-entry catalog, global password, ASCII polish
- [x] v0.4.1 one-liner online installer (in-place conversion, tested in Docker)
- [ ] v0.5 hardening — Lynis audit, artifact signing, CI matrix
- [ ] v1.0 — boot-tested on real PCs, docs user-tested, LTS

## 🤝 Contributing & License

PRs welcome — see [CONTRIBUTING](docs/CONTRIBUTING.md). GPL-3.0, see
[LICENSE](LICENSE). Debian packages follow their own licenses.

<div align="center">

**made with 🐧 and boring, proven tech**

[Website](https://zarigata.github.io/EZpenguin/) · [Releases](https://github.com/zarigata/EZpenguin/releases) · [Issues](https://github.com/zarigata/EZpenguin/issues)

</div>
