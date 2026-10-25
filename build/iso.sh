#!/usr/bin/env bash
# iso.sh — build bootable hybrid BIOS+UEFI live ISO. RUNS INSIDE DOCKER (privileged).
# Usage: iso.sh <arch> <workspace-dir>
set -euo pipefail

ARCH="${1:?arch}"
WS="${2:?workspace}"
source "$WS/config/ezpenguin.cfg"

ROOTFS="/out/rootfs-$ARCH"
OUT="$WS/$EZP_ARTIFACT_DIR"
V="$EZP_VERSION"
log() { printf '\033[1;33m[iso]\033[0m %s\n' "$*" >&2; }

[[ "$ARCH" == "amd64" ]] || { echo "ISO build supports amd64 only for now" >&2; exit 1; }
[[ -d "$ROOTFS" ]] || { echo "no rootfs: $ROOTFS" >&2; exit 1; }
mkdir -p "$OUT"

ISO="$OUT/ezpenguin-$V-$ARCH.iso"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# ----------------------------------------------------------- payload --------
log "packing live root (squashfs, xz)"
mkdir -p "$WORK/live"
# exclude virtual-fs CONTENTS but keep the empty dirs — live-boot's
# init-bottom moves /dev /proc /sys into the new root and needs the
# mount points to exist inside the squashfs
mksquashfs "$ROOTFS" "$WORK/live/filesystem.squashfs" \
    -comp xz -b 256k -Xdict-size 100% -noappend -quiet \
    -wildcards \
    -e "proc/*" "sys/*" "dev/*" "run/*" "tmp/*"
log "squashfs: $(du -h "$WORK/live/filesystem.squashfs" | cut -f1)"

# ------------------------------------------------------------ boot files ----
KVER=$(basename "$(ls "$ROOTFS"/boot/vmlinuz-* | sort -V | tail -1)" | sed 's/vmlinuz-//')
log "kernel: $KVER"
mkdir -p "$WORK/boot/grub"
cp "$ROOTFS/boot/vmlinuz-$KVER" "$WORK/boot/"
cp "$ROOTFS/boot/initrd.img-$KVER" "$WORK/boot/"

cat > "$WORK/boot/grub/grub.cfg" <<'GRUBCFG'
set default=0
set timeout=3
serial --unit=0 --speed=115200
terminal_input console serial
terminal_output console serial
menuentry "EZpenguin GNU/Linux (live)" {
    linux /boot/vmlinuz-KVERPLACEHOLDER boot=live console=tty0 console=ttyS0,115200n8
    initrd /boot/initrd.img-KVERPLACEHOLDER
}
GRUBCFG
sed -i "s/KVERPLACEHOLDER/$KVER/g" "$WORK/boot/grub/grub.cfg"
grep -q "boot=live" "$WORK/boot/grub/grub.cfg" || { echo "grub.cfg generation failed" >&2; exit 1; }

# ------------------------------------------------------------- mkisofs ------
log "building hybrid ISO (BIOS + UEFI) via grub-mkrescue"
grub-mkrescue -o "$ISO" "$WORK" 2>&1 | tail -3 >&2 || true
[[ -s "$ISO" ]] || { echo "grub-mkrescue produced nothing" >&2; exit 1; }

# ------------------------------------------------------------ validate ------
log "validating ISO"
SIZE_MB=$(( $(du -m "$ISO" | cut -f1) ))
(( SIZE_MB <= EZP_MAX_ISO_MB )) || { echo "ISO ${SIZE_MB}MB over budget ${EZP_MAX_ISO_MB}MB" >&2; exit 1; }
# El Torito boot records must exist (BIOS catalog and EFI entry)
ET=$(xorriso -indev "$ISO" -report_el_torito as_mkisofs 2>&1 || true)
echo "$ET" | grep -q -- '-b ' || { echo "ISO missing BIOS El Torito boot image" >&2; exit 1; }
echo "$ET" | grep -q -- '-efi-boot' || { echo "ISO missing UEFI El Torito boot image" >&2; exit 1; }
# volume descriptor readable
xorriso -indev "$ISO" -pvd_info 2>/dev/null | grep -q 'Volume Id' \
    || { echo "ISO primary volume descriptor unreadable" >&2; exit 1; }
# live payload present on the ISO
xorriso -indev "$ISO" -find '/live' 2>/dev/null | grep -q 'filesystem.squashfs' \
    || { echo "ISO missing /live/filesystem.squashfs" >&2; exit 1; }

log "ISO OK: $ISO (${SIZE_MB}MB, BIOS+UEFI El Torito verified)"
ls -lh "$OUT" >&2
