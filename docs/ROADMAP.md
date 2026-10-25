# EZpenguin Roadmap

## v0.1 — Foundation (COMPLETE)
- [x] Project structure & full documentation set
- [x] Docker-based reproducible build pipeline
- [x] Debian bookworm minimal rootfs (amd64)
- [x] EZpenguin identity layer (os-release, /etc/ezpenguin, tools)
- [x] Automated test suite L1–L4 (106 checks, all green)
- [x] First-boot wizard service (QEMU-verified: BIOS + UEFI)
- [x] Flashable disk image (BIOS + UEFI hybrid, 185MB compressed)
- [x] QEMU boot validation integrated in pipeline
- [x] DietPi-style bare-metal installer script (install.sh)

## v0.2 — Installability (COMPLETE)
- [x] Bootable ISO with live installer (hybrid BIOS+UEFI, squashfs live root)
- [x] ARM64 rootfs + image cross-build (QEMU binfmt, boot-tested on QEMU virt/AAVMF)
- [x] Wizard interactive smoke test (QEMU monitor keystroke injection)
- [x] ez-install live/standalone installer (whiptail disk picker)
- [x] ez-doctor health check + ez-net diagnostics tools
- [x] Expanded QA suite + ISO/wizard boot tests in pipeline

## v0.3 — DietPi-parity UX (next)
- [ ] Interactive software catalog (`ez-software`)
- [ ] Headless/SSH-first install mode
- [ ] `ez-config` full system configuration tool
- [ ] Backup/restore of config (`ez-backup`)

## v0.4 — Hardening & Polish
- [ ] Automated secure defaults audit (Lynis baseline)
- [ ] Unattended/preseed install (answer file)
- [ ] Signing of artifacts + signed releases
- [ ] CI pipeline matrix (amd64, arm64)

## v1.0 — First stable release
- [ ] 100% QA checklist green (see QUALITY.md)
- [ ] Boot-tested on 3 real PCs + VirtualBox + QEMU + Pi 4
- [ ] Docs complete & user-tested
- [ ] LTS: security updates for Debian bookworm lifetime

## Beyond
- Board-specific images (Pi, Odroid, Rock Pi)
- Delta updates
- Optional desktop (XFCE) meta-package
- Web-based first-boot UI
