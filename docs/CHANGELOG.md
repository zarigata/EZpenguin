# Changelog

All notable changes to EZpenguin. Format follows Keep-a-Changelog;
versioning is SemVer. Dates are YYYY-MM-DD.

## [0.4.0] — 2026-10-26

Software & UX release: DietPi-scale catalog, global password, polished
terminal experience.

### Added
- Software catalog scaled to 61 installable entries across 6 categories
  (servers, languages/dev, network/VPN, security, monitoring/tools,
  desktops) — docker, python+venv, nodejs, java, go, rust, php, databases,
  cockpit, fail2ban, tailscale, XFCE/LXDE, and more
- Per-entry post-install hooks: services enabled, docker group membership,
  php-fpm started, graphical target set, sensors auto-detected
- `ez-software` v2: DietPi-style category menu → checklist; postcmd
  execution; `categories` command; multi-id `install a b c`
- DietPi-style GLOBAL PASSWORD option: one password for user + root
  (opt-in, wizard prompt or `EZ_GLOBAL_PASSWORD=1` headless; SSH root
  login stays disabled; marker `/etc/ezpenguin/.global-password`)
- Terminal UX: shared banner library (`/usr/local/lib/ezpenguin/banner.sh`)
  with ASCII penguin, branded `/etc/motd` + `/etc/issue`, redesigned
  fastfetch-style `ez-info` panel
- QA suite: catalog field/entry/postcmd-syntax validation, banner/motd
  checks, global-password wiring checks (135 checks total)

## [0.3.0] — 2026-10-25

DietPi-parity UX release: software catalog, headless installs, full
configuration and backup tooling.

### Added
- `ez-software` — software catalog (25 curated entries: servers, VPNs,
  monitoring, desktop): TUI checklist installer, `list`/`search`/
  `install <id>` CLI modes; catalog data at
  `/etc/ezpenguin/software-catalog.list` (single source: `config/`)
- Headless first-boot: drop `firstboot.conf` (key=value) into
  `/boot/` — wizard configures everything unattended (locale, timezone,
  keymap, hostname, user+password, SSH enable, optional upgrade+reboot);
  value charset strictly validated before use
- `ez-config` — full system configuration tool: whiptail menu +
  one-shot commands (hostname/timezone/locale/keymap/ssh/password/wizard)
- `ez-backup` — configuration backup/restore (tarball of /etc state +
  EZpenguin identity), with content preview before restore
- Headless smoke test (`tests/test_headless_smoke.sh`): injects
  firstboot.conf into an image copy, boots with ZERO input, verifies
  unattended completion, user creation, SSH enable, and self-reboot
- QA suite expanded to 131 checks

## [0.2.0] — 2026-10-24

Installability release: live ISO installer, ARM64 cross-builds, interactive
test automation, new diagnostic tools.

### Added
- Bootable hybrid BIOS+UEFI live ISO (`build/iso.sh`, grub-mkrescue +
  squashfs live root via live-boot) with ISO size budget (≤500MB)
- Live installer: first-boot wizard detects live mode and offers
  disk installation; `ez-install` tool (whiptail disk picker, GPT
  BIOS+ESP+root layout, rsync payload, static UUID grub.cfg)
- ARM64/aarch64 support: foreign debootstrap under qemu-user-static,
  arm64 images (ESP+root GPT, arm64-efi GRUB, ttyAMA0 console),
  arm64 boot tests under QEMU virt + AAVMF (`./build/build.sh arm64`)
- `ez-doctor` — system health check (memory, storage, failed units,
  network, security posture) with OK/WARN/FAIL verdict
- `ez-net` — one-command network status & diagnostics
- Interactive wizard smoke test (`tests/test_wizard_smoke.sh`): drives
  the real first-boot wizard in QEMU via monitor keystroke injection
  and verifies full setup completion
- ISO boot tests (BIOS + UEFI) in pipeline (`isotest` stage)
- Test suite expanded (structure, tools, live-boot, timeout hardening)
- Build stages: `iso`, `isotest`, `smoke`, `arm64`; `all` runs the
  complete verified pipeline

### Changed
- Version 0.2.0; artifacts renamed accordingly
- First-boot wizard: live-mode install flow before configuration
- Wizard progress logs mirrored to serial console (stderr) — testable headless
- getty@tty1 masked while wizard owns tty1 (no input contention)
- Disk image uses a slim initramfs (live hooks stripped at image build);
  the ISO carries its own live-enabled initramfs
- Builder image: squashfs-tools, grub BIOS/UEFI binaries,
  qemu-system-arm, AAVMF firmware, isolinux

### Fixed
- live-boot initramfs hooks slowed emulated boots ~10x → disk images now
  regenerate their initrd without live support (ISO unaffected)
- live ISO pivot failure ("mount: /root/dev: mount point does not exist"):
  squashfs excludes now keep empty /dev /proc /sys /run /tmp mount points
- grub-mkrescue arg passing (volid args caused xorriso failure)

## [0.1.0] — 2026-10-24

First working release: complete build→test→image pipeline, bootable
BIOS+UEFI image, verified in QEMU.

### Added
- Full documentation set (ARCHITECTURE, BUILDING, INSTALLATION, TESTING,
  QUALITY, ROADMAP, SECURITY, CONTRIBUTING — 10 MD files)
- Docker-based reproducible build pipeline (amd64): rootfs → tests → image
- Debian bookworm minimal rootfs with EZpenguin identity layer
  (os-release, /etc/ezpenguin, hostname)
- First-boot wizard (`ez-firstboot`): filesystem expansion, locale,
  timezone, keymap, hostname, user creation, optional SSH, package updates
- systemd-networkd DHCP on all wired interfaces (predictable names)
- CLI tools: `ez-info`, `ez-update`, `ez-config`
- Automated QA suite: 106 checks (structure, packages, runtime, security,
  size budget) — all green
- QEMU boot validation (BIOS + UEFI) in pipeline (`boottest` stage)
- Flashable disk image (GPT: BIOS-boot + ESP + root, GRUB BIOS+UEFI,
  serial console, UUID-root) — 185MB compressed
- Rootfs tarball artifact — 155MB compressed
- DietPi-style bare-metal installer (`installer/install.sh`)

### Fixed (during autonomous build/test iterations)
- Inline `#` comments in package lists truncated installs (shell comment)
- grub-pc/grub-efi conflict → hybrid via `*-bin` packages + grub2-common
- macOS case-insensitive FS cannot host Linux rootfs → Docker volume
- Missing GPT BIOS-boot partition prevented BIOS GRUB boot
- update-grub baked build-time `/dev/loop*` into grub.cfg → static
  UUID-based grub.cfg generated at build time
- `quiet` kernel flag hid serial output → verbose boot for headless/tests
