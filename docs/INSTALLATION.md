# EZpenguin Installation

Three ways to get EZpenguin onto a machine — pick one.

## A. Flash & boot (recommended for new PCs)

1. Download `ezpenguin-<ver>-amd64.img.xz` from the build artifacts.
2. Decompress and flash to a USB drive (≥1GB):
   ```bash
   xz -d ezpenguin-*-amd64.img.xz
   dd if=ezpenguin-*-amd64.img of=/dev/sdX bs=4M status=progress conv=fsync
   ```
   *(Windows/macOS: use balenaEtcher — drop the `.img.xz` in directly.)*
3. Boot the target PC from USB (pick the USB entry in BIOS/UEFI boot menu).
4. The **EZpenguin first-boot wizard** runs automatically:
   - expands the filesystem to fill the disk
   - asks locale / timezone / keyboard / hostname
   - creates your user + password
   - updates packages
   - reboots → system ready

Total time on average hardware: **under 5 minutes**.

## B. Live ISO installer

Write `ezpenguin-<ver>-amd64.iso` to USB (`dd if=...iso of=/dev/sdX`) or
attach it to a VM and boot it. The ISO boots a full live environment
(BIOS or UEFI) and the wizard asks:

1. **Install EZpenguin to a disk?** — pick Yes
2. Choose the target disk from a menu (size/model shown)
3. Confirm the erase warning
4. The installer partitions (BIOS-boot + ESP + root), copies the system,
   installs GRUB for BIOS **and** UEFI, and reboots

The installed system then runs the normal first-boot wizard. Choose "No"
to stay in the live session — `sudo ez-install` starts the installer later.

## C. Install from an existing Linux system (DietPi-style)

On any Debian/Ubuntu box you want to convert:

```bash
curl -sL https://ezpenguin.org/install.sh -o install.sh
less install.sh          # always read before piping to bash
sudo bash install.sh /dev/sdX    # target disk
```

The script:
1. wipes the target disk (confirms first)
2. lays out partitions (ESP + root)
3. unpacks the EZpenguin rootfs
4. installs bootloader (GRUB, BIOS or UEFI as detected)
5. reboots into first-boot wizard

## Virtual machines

| Hypervisor | How |
|---|---|
| QEMU/KVM | `qemu-system-x86_64 -m 2G -drive file=ez.img,format=raw -enable-kvm` |
| VirtualBox | New VM → Linux/Debian 64-bit → attach IMG converted to VDI |
| VMware | Use the ISO as installer CD |

## Default credentials

The first-boot wizard forces you to set a user password. There is **no
default password** — the image ships with root login disabled (key or
sudo only) until you configure it.

## Post-install

```bash
ez-update        # update EZpenguin + packages
ez-config        # re-run parts of the wizard
ez-info          # system overview
ez-doctor        # health check (memory/disk/services/network/security)
ez-net           # network status & diagnostics
```
