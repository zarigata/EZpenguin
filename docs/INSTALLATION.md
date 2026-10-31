# Install EZpenguin

Start with a VM or a spare machine while evaluating this early-stage OS.
Published images are available on [GitHub Releases](https://github.com/zarigata/EZpenguin/releases).
Flashing a drive or installing to a disk **erases that selected target**.

## Choose an installation method

| Method | Environment | Result |
|---|---|---|
| Flashable `.img.xz` | amd64 PC, compatible UEFI ARM64 system, VM | Dedicated bootable EZpenguin disk |
| Live `.iso` | amd64 BIOS / UEFI PC or VM | Live session with optional disk installer |
| Online installer | Debian / Ubuntu environment | Container conversion or target-disk installation |
| Local installer script | Linux host with required disk tools | amd64 target-disk installation using a local rootfs |

ARM64 images target UEFI boot; they are not universal board-specific images.
Secure Boot and individual device compatibility require separate validation.

## Flash a disk image

1. Download the `amd64.img.xz` or `arm64.img.xz` matching your hardware.
2. Write it with a flashing tool. Some tools accept compressed images directly;
   others require decompression with `xz -d` first.
3. Verify the target drive, flash, and boot it.
4. Complete the first-boot wizard: locale, timezone, keyboard, hostname, user,
   password, optional SSH, package updates, and reboot.

The wizard attempts to expand the root filesystem. Setup time depends on
hardware, emulation, and network speed; there is no universal time guarantee.

## Live ISO

Attach the amd64 ISO to a VM, or write it to a USB drive, then boot it in BIOS
or UEFI mode. The wizard offers to install to a disk. Choose the target disk,
confirm the erase warning, and continue. Decline to remain in the live session;
`sudo ez-install` starts installation later.

## Online installer

Review the actual script before running it as root:

~~~bash
curl -fsSL https://raw.githubusercontent.com/zarigata/EZpenguin/main/installer/online-installer.sh -o ezpenguin-install.sh
less ezpenguin-install.sh
sudo bash ezpenguin-install.sh
~~~

Requirements: a supported `amd64` / `arm64` environment with `curl`, `tar`,
and `xz`, network access to GitHub Releases, and root access.

The script detects common container environments; **VMs are not automatically
treated as containers**.

- In a detected container, it extracts the rootfs over the running system,
  replacing the userland. Existing software can be overwritten.
- Outside a detected container, it prompts for a target disk, confirms erasure,
  partitions it, installs a rootfs and GRUB, then requests reboot.
- `EZP_INPLACE=1` forces in-place conversion outside a detected container.
  This is an advanced override that replaces the running system; use a disposable
  environment and do not treat it as a supported upgrade of a valuable host.
- `EZP_NO_REBOOT=1` skips the final reboot / stop action.
- `EZP_TARBALL=/path/to/rootfs.tar.xz` uses a local rootfs instead of release lookup.
- `EZP_ARCH=amd64` or `arm64` overrides architecture detection.

The installer does not currently validate the downloaded rootfs against a signed
checksum. Artifact signing is roadmap work.

### Disposable container evaluation

This checks the converted userland without granting the container access to
host block devices. It does **not** test a kernel, bootloader, systemd, or the
automatic first-boot wizard.

~~~bash
docker run -d --name ezp-demo ubuntu:24.04 sleep infinity
docker exec ezp-demo bash -c 'apt-get update -qq && apt-get install -y -qq curl xz-utils'
docker exec ezp-demo curl -fsSL https://raw.githubusercontent.com/zarigata/EZpenguin/main/installer/online-installer.sh -o /tmp/ezpenguin-install.sh
docker exec ezp-demo cat /tmp/ezpenguin-install.sh
# After reviewing the script:
docker exec -e EZP_NO_REBOOT=1 ezp-demo bash /tmp/ezpenguin-install.sh
docker exec ezp-demo ez-info
# Remove the disposable environment when finished:
docker rm -f ezp-demo
~~~

A container restart reruns the configured entrypoint; it does not boot the image's
init system. Use an image / ISO in QEMU to test a complete boot.

## Local disk installer (amd64)

Clone this repository, obtain an amd64 rootfs tarball from Releases or a local
build, and inspect `installer/install.sh`. It requires the disk tools listed in
the script, including `sgdisk`, filesystem tools, `rsync`, and GRUB.

~~~bash
sudo bash installer/install.sh /dev/sdX /path/to/ezpenguin-0.4.1-amd64-rootfs.tar.xz
~~~

Replace both placeholder paths. **The target disk is erased after confirmation.**
This script is separate from the online installer and does not automatically
download its rootfs. For ARM64, use the matching UEFI image or the ARM64-aware
online installer.

## Headless setup

Mount the flashed root partition and place `firstboot.conf` in its `/boot/`
directory before first boot:

~~~ini
EZ_LOCALE=en_US.UTF-8
EZ_TIMEZONE=America/Sao_Paulo
EZ_KEYMAP=us
EZ_HOSTNAME=homelab
EZ_USERNAME=penguin
EZ_PASSWORD=replace-with-a-unique-password
EZ_SSH_ENABLE=1
EZ_UPGRADE=1
EZ_REBOOT=1
~~~

Values accept `[A-Za-z0-9_.:/+@-]` only. Other characters are rejected.
Omit `EZ_PASSWORD` to create a locked account; configure a working access method
before relying on remote login. Use a unique password, protect the configuration
file, and remove the retained `firstboot.conf.applied` after setup because it may
contain that password.

`EZ_GLOBAL_PASSWORD=1`, together with `EZ_PASSWORD`, optionally unlocks root
console login using the same password as the created user. SSH root login remains
disabled. Leave this option unset to keep root password login locked.

## Virtual machines and defaults

Use the amd64 live ISO in VirtualBox / VMware, or attach a decompressed disk image
to QEMU. ARM64 testing uses the QEMU `virt` machine with AAVMF UEFI firmware.
See [BUILDING](BUILDING.md) and [TESTING](TESTING.md).

There is no default user password. Root password login starts locked and the
wizard creates your user. Optional global-password setup changes the root
console-login behavior described above.

## After installation

~~~bash
ez-info
ez-doctor
ez-net
sudo ez-config
sudo ez-update
sudo ez-software
~~~

See the [software catalog](../config/software-catalog.list) for install recipes.
