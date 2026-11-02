# Changelog

All notable changes to EZpenguin. Format follows Keep-a-Changelog;
versioning is SemVer. Dates are YYYY-MM-DD.

## [1.1.0] — 2026-11-02

The software catalog goes from 61 to 261 entries and gains a full-screen
terminal UI: `ez-soft` (also reached via `ez-software` on a real TTY).

### Added
- software catalog: 261 entries across server (55), tools (73), dev (49),
  network (35), security (29), desktop (20) — every package token verified
  present in Debian bookworm (`apt-cache policy`, 295/295 green).
- `ez-soft` — pure-bash ANSI full-screen TUI (no new dependencies, works
  over SSH): two-pane category/entry browser, live filter (`/`), detail
  pane, multi-select (`Space`), batch install with per-entry status,
  quit confirmation; `ez-software` delegates to it automatically when
  stdin+stdout are TTYs.
- `tests/test_ezsoft.sh` — 33-assertion self-check for the TUI.
- `tests/matrix/qualify-tui.sh` — drives the real TUI through a pty
  (setup/render/toggle/install/quit-confirm/delegation) on
  debian:12, ubuntu:24.04 and debian:11 — 18/18 PASS.

### Fixed
- catalog ids now match `^[a-z0-9-]+$` (`lua5.4`→`lua54`, `lua5.3`→`lua53`,
  `bonnie++`→`bonnie`) — grep- and awk-based counters agreed at 261 after.
- `gogs` package is not in bookworm → replaced with `gitweb`.
- `ez-software`: undefined `C_OK` under `set -u` crashed the summary after
  every install; EOF during key-read now quits cleanly; 0x0 pty size falls
  back to 24x80.

## Unreleased — project presentation

- Adopted the approved wild-cartoon mascot and Y2K website theme.
- Added FeverDream.dev attribution and a complete on-site wiki: 61 software
  recipes, base packages, setup, system tools, troubleshooting, and reference guides.
- Kept documentation navigation on the public website rather than repository pages.

- Rebuilt the responsive website with software search, category filters, copyable
  commands, keyboard-accessible install tabs, and a clear path to GitHub stars.
- Rewrote README and installation guidance with current artifacts and accurate
  container / VM behavior, architecture boundaries, and project status.
- Added canonical and social metadata, JSON-LD, sitemap, and a share image.
- Added host-side website integrity checks and checks before Pages deployment.
- Removed comparison branding from documentation, comments, and CLI messages.

## [1.0.0] — 2026-11-01

First stable release. The one-liner installer is now proven across the full
compatibility matrix, including real in-place conversion of a booted Debian 12
system (QEMU) that reboots from disk into a healthy EZpenguin with 0 failed
systemd units.

### Fixed
- installer: strict OS gating for in-place conversion — Debian 11/12 and
  Ubuntu 22.04/24.04 only; non-Debian systems and Debian derivatives
  (Linux Mint detected via its packages, since its os-release impersonates
  `ID=ubuntu`) are refused safely before anything is modified.
- installer: `/usr` overwrite on booted systems uses `tar --unlink-first`
  — `cp -a` overwrote running binaries' text pages in place (journald/PID1
  SIGSEGV mid-conversion on Ubuntu).
- installer: mount capture looped per-target (`findmnt` accepts only one
  target; multi-arg call silently captured nothing) with `/proc/mounts`
  fallback; fstab root-line check reads the mount-target field, not source.
- installer: priv-toolbox wrappers snapshot the loader/libpath so EXIT
  cleanup cannot call a dead wrapper (masked real exit codes with `set -u`).
- installer: downloaded artifact is `xz -t`-validated before any destructive
  step (a 404 page used to fail only mid-conversion).
- installer: ERR trap reports abort line/rc for diagnosability.
- rootfs/installer: mask legacy `networking.service` (ifupdown) — userland
  uses systemd-networkd and ships no `ifup`; the generated unit failed on
  every boot.
- rootfs: `systemd-networkd-wait-online` drop-in uses the absolute
  `/usr/lib/systemd/...` path (bare name failed with 203/EXEC — unit not on
  systemd's default unit PATH) — the last boot-failed unit, now 0.
- ez-software: `categories`/`tui` field-splitting used `awk -F'|'` on
  TAB-joined parse output (every entry collapsed into one blank category).

### Verified
- faults tier 11/11 PASS; container matrix 18/18 PASS (5 supported rows
  convert + 7 reject rows refused safely, incl. Linux Mint 22).
- cli tier 36 PASS / 0 FAIL / 3 BLOCKED (non-TTY-only probes).
- catalog tier: all 61 entries functionally probed in guests.
- vm tier: debian12-inplace-amd64 — install → reboot from disk →
  `ID=ezpenguin`, `failed-count=0`, outbound `https:200`.
- one-liner smoke-tested via `EZP_API_URL` override against a draft release.

## [0.4.1] — 2026-10-27

One-liner online installer + GitHub Pages.

### Added
- `installer/online-installer.sh` — one-liner:
  `bash -c "$(curl -sSfL https://raw.githubusercontent.com/zarigata/EZpenguin/main/installer/online-installer.sh)"`
  - auto-detects container vs bare-metal, amd64/arm64
  - container/VM mode: IN-PLACE conversion of the running system
    (Docker DNS/hostname preserved, machine-id regenerated, wizard armed),
    then reboots (container restart = boot)
  - bare-metal mode: disk picker, GPT BIOS+ESP+root, GRUB, static grub.cfg
  - tested end-to-end on ubuntu:24.04 (convert → commit → fresh boot →
    EZpenguin identity, working apt, wizard pending)
- GitHub Pages landing site (`docs/index.html` →
  https://zarigata.github.io/EZpenguin/)
- README overhaul: one-liner install section, catalog table, roadmap,
  centered landing layout

### Fixed
- `banner.sh` tty-detection could deadlock when stdout was a pipe
  (grep reading its own stdout) — now plain `-t 1` test; installer also
  hotpatches older tarballs

## [0.4.0] — 2026-10-26

Software & UX release: Expanded catalog, global password, polished
terminal experience.

### Added
- Software catalog scaled to 61 installable entries across 6 categories
  (servers, languages/dev, network/VPN, security, monitoring/tools,
  desktops) — docker, python+venv, nodejs, java, go, rust, php, databases,
  cockpit, fail2ban, tailscale, XFCE/LXDE, and more
- Per-entry post-install hooks: services enabled, docker group membership,
  php-fpm started, graphical target set, sensors auto-detected
- `ez-software` v2: category menu → checklist; postcmd
  execution; `categories` command; multi-id `install a b c`
- Optional GLOBAL PASSWORD option: one password for user + root
  (opt-in, wizard prompt or `EZ_GLOBAL_PASSWORD=1` headless; SSH root
  login stays disabled; marker `/etc/ezpenguin/.global-password`)
- Terminal UX: shared banner library (`/usr/local/lib/ezpenguin/banner.sh`)
  with ASCII penguin, branded `/etc/motd` + `/etc/issue`, redesigned
  fastfetch-style `ez-info` panel
- QA suite: catalog field/entry/postcmd-syntax validation, banner/motd
  checks, global-password wiring checks (135 checks total)

## [0.3.0] — 2026-10-25

Appliance UX release: software catalog, headless installs, full
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
- bare-metal installer (`installer/install.sh`)

### Fixed (during autonomous build/test iterations)
- Inline `#` comments in package lists truncated installs (shell comment)
- grub-pc/grub-efi conflict → hybrid via `*-bin` packages + grub2-common
- macOS case-insensitive FS cannot host Linux rootfs → Docker volume
- Missing GPT BIOS-boot partition prevented BIOS GRUB boot
- update-grub baked build-time `/dev/loop*` into grub.cfg → static
  UUID-based grub.cfg generated at build time
- `quiet` kernel flag hid serial output → verbose boot for headless/tests
