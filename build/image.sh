#!/usr/bin/env bash
# image.sh — package rootfs into artifacts. RUNS INSIDE DOCKER (privileged).
# Usage: image.sh <arch> <workspace-dir>
set -euo pipefail

ARCH="${1:?arch}"
WS="${2:?workspace}"
source "$WS/config/ezpenguin.cfg"

ROOTFS="/out/rootfs-$ARCH"
OUT="$WS/$EZP_ARTIFACT_DIR"
V="$EZP_VERSION"
log() { printf '\033[1;35m[image]\033[0m %s\n' "$*" >&2; }

[[ -d "$ROOTFS" ]] || { echo "no rootfs: $ROOTFS" >&2; exit 1; }
mkdir -p "$OUT"

# ---------------------------------------------------------- rootfs tarball --
TARBALL="$OUT/ezpenguin-$V-$ARCH-rootfs.tar.xz"
if [[ -s "$TARBALL" && "${FORCE_IMAGE:-0}" != "1" ]]; then
    log "tarball exists, skipping (FORCE_IMAGE=1 to rebuild): $TARBALL"
else
    log "creating rootfs tarball"
    tar -C "$ROOTFS" \
        --exclude='./dev/*' --exclude='./proc/*' --exclude='./sys/*' \
        --exclude='./tmp/*' --exclude='./run/*' \
        --numeric-owner --xattrs --acls \
        -cJf "$TARBALL" .
    log "tarball: $TARBALL ($(du -h "$TARBALL" | cut -f1))"
fi

# ------------------------------------------------------------ disk image ----
IMG="$OUT/ezpenguin-$V-$ARCH.img"
log "creating flashable image $IMG"

# serial console: amd64=ttyS0 (16550A), arm64=ttyAMA0 (PL011, QEMU -M virt)
if [[ "$ARCH" == "arm64" ]]; then
    CONSOLE="console=tty0 console=ttyAMA0,115200"
else
    CONSOLE="console=tty0 console=ttyS0,115200n8"
fi

# size = rootfs usage + 400MB headroom, min 1.5GB
ROOT_MB=$(( $(du -sm --apparent-size "$ROOTFS" | cut -f1) + 400 ))
(( ROOT_MB < 1500 )) && ROOT_MB=1500
if [[ "$ARCH" == "arm64" ]]; then
    truncate -s "$(( ROOT_MB + 260 ))M" "$IMG"
    log "partitioning (GPT: ESP 260MB + root ${ROOT_MB}MB) — arm64/UEFI only"
    sgdisk -Z "$IMG" >/dev/null 2>&1 || { apt-get update >/dev/null && apt-get install -y gdisk >/dev/null; }
    sgdisk -n 1:0:+260M  -t 1:ef00 -c 1:ESP "$IMG"
    sgdisk -n 2:0:0      -t 2:8300 -c 2:root "$IMG"
    sgdisk -p "$IMG" >&2
    PN="p1 p2"
else
    truncate -s "$(( ROOT_MB + 260 ))M" "$IMG"
    log "partitioning (GPT: BIOS-boot 1M + ESP 260MB + root ${ROOT_MB}MB)"
    sgdisk -Z "$IMG" >/dev/null 2>&1 || { apt-get update >/dev/null && apt-get install -y gdisk >/dev/null; }
    sgdisk -n 1:0:+1M    -t 1:ef02 -c 1:BIOSBOOT "$IMG"
    sgdisk -n 2:0:+260M  -t 2:ef00 -c 2:ESP "$IMG"
    sgdisk -n 3:0:0      -t 3:8300 -c 3:root "$IMG"
    sgdisk -p "$IMG" >&2
    PN="p1 p2 p3"
fi

LOOP=$(losetup --find --show -P "$IMG")
trap 'losetup -d "$LOOP" 2>/dev/null || true' EXIT
log "loop device: $LOOP"

# containers lack udev — force partition scan and wait for nodes
partprobe "$LOOP" 2>/dev/null || partx -u "$LOOP" 2>/dev/null || true
for _ in $(seq 1 10); do
    ALL=1
    for p in $PN; do [[ -b "${LOOP}${p}" ]] || ALL=0; done
    (( ALL )) && break
    # manual node creation fallback
    for p in $PN; do
        pth="${LOOP}${p}"
        sys="${pth/\/dev\//\/sys/block/$(basename "$LOOP")/}"
        if [[ ! -b "$pth" && -f "${sys}/dev" ]]; then
            majmin=$(cat "${sys}/dev"); mkdir -p /dev
            mknod "$pth" b "${majmin%%:*}" "${majmin##*:}" 2>/dev/null || true
        fi
    done
    sleep 1
done
ALL=1
for p in $PN; do [[ -b "${LOOP}${p}" ]] || ALL=0; done
(( ALL )) || { echo "partitions missing on $LOOP" >&2; exit 1; }

log "formatting"
if [[ "$ARCH" == "arm64" ]]; then
    ESP="${LOOP}p1"; ROOT="${LOOP}p2"
else
    # p1=BIOSBOOT (raw, no fs) p2=ESP p3=root
    ESP="${LOOP}p2"; ROOT="${LOOP}p3"
fi
mkfs.vfat -F32 -n EZP_BOOT "$ESP" >/dev/null
mkfs.ext4 -L EZP_ROOT -q -E lazy_itable_init=0 "$ROOT"

    # mount root first — then create ESP mountpoint INSIDE the new fs
    MNT=$(mktemp -d)
    mount "$ROOT" "$MNT"
    mkdir -p "$MNT/boot/efi"
    mount "$ESP" "$MNT/boot/efi"
    trap 'umount "$MNT/boot/efi" "$MNT" 2>/dev/null; losetup -d "$LOOP" 2>/dev/null; rm -rf "$MNT"' EXIT

    log "copying rootfs"
    rsync -aHAX --numeric-ids "$ROOTFS/" "$MNT/"

    # chroot for kernel+grub install
    for d in dev proc sys; do mount --bind "/$d" "$MNT/$d"; done
    trap 'umount "$MNT/dev" "$MNT/proc" "$MNT/sys" "$MNT/boot/efi" "$MNT" 2>/dev/null; losetup -d "$LOOP" 2>/dev/null; rm -rf "$MNT"' EXIT

    # disk image never boots live — drop live-boot from ITS initramfs.
    # live-boot's hooks triple the initrd size and its device scan makes
    # emulated boots crawl; the ISO carries its own live-enabled initrd.
    log "regenerating slim initramfs (no live hooks)"
    KVER=$(basename "$(ls "$MNT"/boot/vmlinuz-* | sort -V | tail -1)" | sed 's/vmlinuz-//')
    chroot "$MNT" /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin \
        DEBIAN_FRONTEND=noninteractive /bin/bash -exc '
            if dpkg -s live-boot >/dev/null 2>&1; then
                dpkg --remove --force-depends live-boot live-boot-initramfs-tools >/dev/null 2>&1 || true
                update-initramfs -u -k '"$KVER"' 2>&1 | tail -2 >&2
            fi
        ' >&2

    cat > "$MNT/etc/fstab" <<EOF
LABEL=EZP_ROOT  /           ext4  defaults,noatime  0 1
LABEL=EZP_BOOT  /boot/efi   vfat  defaults          0 2
tmpfs           /tmp        tmpfs defaults,nosuid   0 0
EOF

    log "installing GRUB ($( [[ "$ARCH" == "arm64" ]] && echo 'arm64-efi' || echo 'BIOS + UEFI' ))"
    # serial console on ttyS0/ttyAMA0 — enables headless use AND automated boot tests
    cat > "$MNT/etc/default/grub" <<GRUBCFG
GRUB_DEFAULT=0
GRUB_TIMEOUT=3
GRUB_DISTRIBUTOR="EZpenguin"
GRUB_CMDLINE_LINUX_DEFAULT="quiet"
GRUB_CMDLINE_LINUX="$CONSOLE"
GRUB_TERMINAL="console serial"
GRUB_SERIAL_COMMAND="serial --unit=0 --speed=115200"
GRUBCFG
    ROOT_UUID=$(blkid -s UUID -o value "$ROOT")
    [[ -n "$ROOT_UUID" ]] || { echo "cannot determine root UUID" >&2; exit 1; }
    log "root UUID: $ROOT_UUID"

    # static, deterministic grub.cfg (update-grub probes build-time devices
    # and would bake /dev/loop* into the image; UUID is generated here)
    KVER=$(basename "$(ls "$MNT"/boot/vmlinuz-* | sort -V | tail -1)" | sed 's/vmlinuz-//')
    log "kernel: $KVER"
    if [[ "$ARCH" == "arm64" ]]; then
        GRUB_CHROOT='
            grub-install --target=arm64-efi --efi-directory=/boot/efi --boot-directory=/boot --no-nvram --removable || { echo "arm64 grub install failed" >&2; exit 1; }
            echo "grub: arm64-efi=1" >&2
        '
    else
        GRUB_CHROOT='
            efi_ok=1; bios_ok=1
            grub-install --target=x86_64-efi --efi-directory=/boot/efi --boot-directory=/boot --no-nvram --removable || efi_ok=0
            grub-install --target=i386-pc --boot-directory=/boot '"$LOOP"' || bios_ok=0
            [ "$efi_ok" = 1 ] || [ "$bios_ok" = 1 ] || { echo "both grub installs failed" >&2; exit 1; }
            echo "grub: efi=$efi_ok bios=$bios_ok" >&2
        '
    fi
    chroot "$MNT" /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin \
        DEBIAN_FRONTEND=noninteractive /bin/bash -exc "$GRUB_CHROOT" >&2

    mkdir -p "$MNT/boot/grub"
    cat > "$MNT/boot/grub/grub.cfg" <<GRUBCFG
set default=0
set timeout=3
serial --unit=0 --speed=115200
terminal_input console serial
terminal_output console serial
menuentry "EZpenguin GNU/Linux" {
    search --no-floppy --fs-uuid --set=root $ROOT_UUID
    linux /boot/vmlinuz-$KVER root=UUID=$ROOT_UUID rw $CONSOLE
    initrd /boot/initrd.img-$KVER
}
menuentry "EZpenguin GNU/Linux (recovery mode)" {
    search --no-floppy --fs-uuid --set=root $ROOT_UUID
    linux /boot/vmlinuz-$KVER root=UUID=$ROOT_UUID rw single $CONSOLE
    initrd /boot/initrd.img-$KVER
}
GRUBCFG
    grep -q "root=UUID=$ROOT_UUID" "$MNT/boot/grub/grub.cfg" || exit 1

    log "finalizing image"
    sync
    umount "$MNT/dev" "$MNT/proc" "$MNT/sys"
    umount "$MNT/boot/efi" "$MNT"
    losetup -d "$LOOP"
    trap - EXIT

    log "compressing image"
    xz -T0 -1 -f "$IMG"
    log "image: $IMG.xz ($(du -h "$IMG.xz" | cut -f1))"

# ------------------------------------------------------------ validate -----
log "validating artifacts"
tar -tJf "$TARBALL" > /tmp/tarlist.txt
grep -qx './bin/sh' /tmp/tarlist.txt || grep -qx './usr/bin/sh' /tmp/tarlist.txt || { echo "tarball missing sh" >&2; exit 1; }
ENTRIES=$(tar -tJf "$TARBALL" | wc -l)
(( ENTRIES > 5000 )) || { echo "tarball suspiciously small: $ENTRIES entries" >&2; exit 1; }
if [[ -f "${IMG}.xz" ]]; then
    # head closing the pipe SIGPIPEs xzcat — tolerate via pipefail-off region
    set +o pipefail
    SIG=$(xzcat "${IMG}.xz" 2>/dev/null | head -c 520 | tail -c 8)
    set -o pipefail
    [[ "$SIG" == "EFI PART" ]] || { echo "image missing GPT signature" >&2; exit 1; }
    IMGXZ_MB=$(( $(du -m "${IMG}.xz" | cut -f1) ))
    (( IMGXZ_MB <= 400 )) || { echo "img.xz ${IMGXZ_MB}MB over 400MB budget" >&2; exit 1; }
fi
log "validation OK (tarball $ENTRIES entries, GPT signature present)"

log "artifacts done:"
ls -lh "$OUT" >&2
