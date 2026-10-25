# EZpenguin Testing Strategy

## Philosophy

> A build that isn't tested is broken by definition. Tests run before
> artifacts are packaged; failing tests abort the pipeline.

## Test levels

```
L1  Static / structural      cheap, seconds
L2  Rootfs integrity         chroot + apt + dpkg checks
L3  Runtime / services       boot simulation, systemd units
L4  Artifacts                images are valid, bootable structures
```

### L1 — Static (host-side)
- `test_structure.sh` — all required files/dirs present in rootfs
- `test_docs.sh` — every documented command/tool exists
- config sanity — package lists parse, no duplicates/exclusions conflicts

### L2 — Rootfs integrity (in chroot, inside Docker)
- `test_packages.sh`:
  - `dpkg --audit` clean (no half-installed packages)
  - every package in `packages-base.list` is installed
  - every package in `packages-exclude.list` is NOT installed
  - no broken dependencies (`apt-get check`)
  - `apt-get update` succeeds against pinned sources
- `test_identity.sh` — `/etc/ezpenguin/version`, os-release, hostname

### L3 — Runtime (systemd-nspawn style / container boot)
- `test_boot.sh`:
  - init system present (`/sbin/init` → systemd)
  - all enabled EZpenguin services are valid units (`systemctl verify`)
  - first-boot script is executable and syntactically valid (`bash -n`)
  - kernel + initramfs present and matched
- `test_users.sh` — no default/unhashed passwords in `/etc/shadow`

### L4 — Artifacts & Boot (every build)
- `build/image.sh` validation — tarball integrity, GPT signature on the
  image, entry-count sanity
- `build/iso.sh` validation — El Torito BIOS + UEFI boot records present,
  volume descriptor, ISO size budget
- `tests/test_boot_vm.sh` — boots the actual IMG in QEMU (TCG) with serial
  console; amd64 tested on BIOS (SeaBIOS) **and** UEFI (OVMF); arm64 tested
  on QEMU `virt` machine with AAVMF firmware
- `tests/test_boot_vm_retry.sh` — one retry to separate emulator timing
  flakiness from real defects (2 consecutive fails = real failure)
- `tests/test_iso_boot.sh` — boots the live ISO (BIOS + UEFI) and verifies
  the live userspace starts and reaches the wizard
- `tests/test_wizard_smoke.sh` — interactive smoke test: injects real
  keystrokes via the QEMU monitor (`sendkey`), walks the entire first-boot
  wizard (locale, timezone, keymap, hostname, user+password, SSH), and
  verifies "first-boot setup complete" on the serial console

## Running

```bash
./build/build.sh test       # QA suite against the rootfs (in Docker)
./build/build.sh boottest   # QEMU boot tests
./build/build.sh isotest    # live ISO boot tests
./build/build.sh smoke      # interactive wizard walkthrough
```

Exit code 0 = all pass. Output is TAP-ish: `ok N name` / `not ok N name`,
plus a summary and failed-test list.

## Continuous improvement loop

1. Build
2. Test
3. If red → fix → rebuild (no partial merges)
4. Track pass rate in `artifacts/test-report.txt`
5. Any new bug found in the wild becomes a new test first, then a fix

## Manual/smoke testing (when hardware available)

- Boot on: 1× BIOS PC, 1× UEFI PC, 1× Raspberry Pi 4, VirtualBox
- Verify wizard completes and reboots into a login prompt
- Verify `ez-info` output and network connectivity
