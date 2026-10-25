# Building EZpenguin

## Prerequisites

Only one hard requirement: **Docker** (or any OCI-compatible runtime).

```bash
docker version   # must work without sudo
```

Disk: ~5GB free. RAM: 2GB+. Internet connection for package downloads.

## Quick build

```bash
./build/build.sh
```

That's it. On success you'll find in `artifacts/`:

| File | Description |
|---|---|
| `ezpenguin-<ver>-amd64-rootfs.tar.xz` | Bare rootfs (for custom images) |
| `ezpenguin-<ver>-amd64.img.xz` | Flashable disk image (BIOS+UEFI) |
| `ezpenguin-<ver>-amd64.iso` | Bootable live/install ISO |
| `ezpenguin-<ver>-arm64-rootfs.tar.xz` | ARM64 rootfs |

## Pipeline stages

`build.sh` runs these stages in order; each can be run alone:

```bash
./build/build.sh rootfs     # build amd64 rootfs in Docker
./build/build.sh rootfs arm64
./build/build.sh test       # run QA suite against the rootfs
./build/build.sh image      # package flashable image + rootfs tarball
./build/build.sh boottest   # QEMU boot test (BIOS + UEFI)
./build/build.sh iso        # build hybrid live ISO
./build/build.sh isotest    # boot the ISO in QEMU (BIOS + UEFI)
./build/build.sh smoke      # interactive wizard walkthrough (sendkey automation)
./build/build.sh arm64      # full arm64 pipeline (rootfs→test→image→boottest)
./build/build.sh all        # complete amd64 pipeline (default)
```

Fail-fast: any stage returning non-zero aborts the pipeline.

## Configuration

- `config/packages-base.list` — packages in every image (one per line)
- `config/packages-exclude.list` — packages pulled by deps but unwanted
- `config/ezpenguin.cfg` — version, suite, mirror, branding, size budgets
- `rootfs-overlay/` — anything here is copied verbatim into the image

## Cross-building ARM64

ARM64 builds use a **foreign debootstrap**: stage 1 runs natively on the
host, stage 2 executes inside the chroot under `qemu-aarch64-static`
(user-mode emulation). The qemu interpreter is copied into the chroot
during the build and removed from the final artifact. binfmt_misc is
registered automatically when needed (privileged builder container).

The arm64 image is UEFI-only (no legacy BIOS on aarch64): GPT with
ESP + root, GRUB arm64-efi, serial console on `ttyAMA0` (PL011).

```bash
./build/build.sh arm64     # ~4× slower than amd64 (emulation)
```

## Caching

Package downloads are cached in a Docker volume (`ezpenguin-apt-cache`)
so repeated builds are fast. Delete it with:

```bash
docker volume rm ezpenguin-apt-cache
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| `debootstrap: command not found` | You're not in Docker; run via `build.sh` |
| Tests fail on `apt` | Check network / mirror reachability in container |
| ARM build hangs | Ensure binfmt registered: `docker run --privileged tonistiigi/binfmt --install arm64` |
| No space left | `docker system prune` and retry |
