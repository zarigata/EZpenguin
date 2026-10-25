#!/usr/bin/env bash
# EZpenguin installer — DietPi-style: install EZpenguin onto a disk from
# any running Linux (or from within the live image).
#
# Usage: sudo ./install.sh /dev/sdX [rootfs.tar.xz]
set -euo pipefail

TARGET_DISK="${1:?usage: install.sh /dev/sdX [rootfs.tar.xz]}"
TARBALL="${2:-./ezpenguin-latest-amd64-rootfs.tar.xz}"
VERSION="$(cat "$(dirname "$0")/../config/ezpenguin.cfg" 2>/dev/null | grep -oP 'EZP_VERSION="\K[^"]+' || echo '0.1.0')"

log() { printf '\033[1;36m[installer]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[installer] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run as root (sudo)"
[[ -b "$TARGET_DISK" ]] || die "$TARGET_DISK is not a block device"
[[ -f "$TARBALL" ]] || die "rootfs tarball not found: $TARBALL"

for cmd in sgdisk mkfs.vfat mkfs.ext4 rsync grub-install; do
    command -v "$cmd" >/dev/null || die "missing tool: $cmd (apt install gdisk dosfstools e2fsprogs rsync grub-pc)"
done

# ---------------------------------------------------------------- safety ---
if command -v whiptail >/dev/null; then
    whiptail --yesno "This will ERASE EVERYTHING on $TARGET_DISK.\n\nProceed?" 10 60 3>&1 1>&2 2>&3 \
        || die "aborted by user"
fi

echo -n "Type 'YES' to wipe $TARGET_DISK: "; read -r REPLY
[[ "$REPLY" == "YES" ]] || die "aborted"

umount "$TARGET_DISK"* 2>/dev/null || true
swapoff "$TARGET_DISK"* 2>/dev/null || true

# ------------------------------------------------------------ partitions ---
log "partitioning $TARGET_DISK (BIOS-boot 1M + ESP 260MB + root)"
sgdisk -Z "$TARGET_DISK"
sgdisk -n 1:0:+1M    -t 1:ef02 -c 1:BIOSBOOT "$TARGET_DISK"
sgdisk -n 2:0:+260M  -t 2:ef00 -c 2:ESP "$TARGET_DISK"
sgdisk -n 3:0:0      -t 3:8300 -c 3:root "$TARGET_DISK"
partprobe "$TARGET_DISK"; sleep 2

if [[ -e "${TARGET_DISK}1" ]]; then ESP="${TARGET_DISK}2"; ROOT="${TARGET_DISK}3"
elif [[ -e "${TARGET_DISK}p2" ]]; then ESP="${TARGET_DISK}p2"; ROOT="${TARGET_DISK}p3"
else die "cannot find partitions on $TARGET_DISK"; fi

log "formatting"
mkfs.vfat -F32 -n EZP_BOOT "$ESP"
mkfs.ext4 -L EZP_ROOT -q "$ROOT"

# ------------------------------------------------------------- install -----
MNT=$(mktemp -d)
mkdir -p "$MNT/boot/efi"
mount "$ROOT" "$MNT"; mount "$ESP" "$MNT/boot/efi"

cleanup() { umount -R "$MNT" 2>/dev/null || true; rm -rf "$MNT"; }
trap cleanup EXIT

log "extracting rootfs ($TARBALL)"
tar -xJf "$TARBALL" -C "$MNT" --numeric-owner

cat > "$MNT/etc/fstab" <<EOF
LABEL=EZP_ROOT  /           ext4  defaults,noatime  0 1
LABEL=EZP_BOOT  /boot/efi   vfat  defaults          0 2
tmpfs           /tmp        tmpfs defaults,nosuid   0 0
EOF

for d in dev proc sys; do mount --bind "/$d" "$MNT/$d"; done

log "installing bootloader"
UEFI=0
[[ -d /sys/firmware/efi ]] && UEFI=1

chroot "$MNT" /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin \
    DEBIAN_FRONTEND=noninteractive /bin/bash -exc '
        grub-install --target=x86_64-efi --efi-directory=/boot/efi --boot-directory=/boot --no-nvram --removable || true
        grub-install --target=i386-pc --boot-directory=/boot '"$TARGET_DISK"' || true
        update-grub || grub-mkconfig -o /boot/grub/grub.cfg
    ' >&2

umount "$MNT/dev" "$MNT/proc" "$MNT/sys"; sync

log "done. Reboot into EZpenguin $VERSION — first-boot wizard will start."
echo
echo "  Next: umount everything, reboot, remove USB if any."
echo "  The first-boot wizard runs automatically on tty1."
