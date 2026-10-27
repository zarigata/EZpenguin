#!/usr/bin/env bash
# EZpenguin online installer — DietPi-style one-liner.
#
#   bash -c "$(curl -sSfL https://raw.githubusercontent.com/zarigata/EZpenguin/main/installer/online-installer.sh)"
#
# What it does:
#   • Downloads the latest EZpenguin rootfs from GitHub releases
#   • CONTAINERS/VMs (default): in-place conversion — replaces the running
#     system userland with EZpenguin, then reboots (container restart = boot)
#   • BARE METAL: pick a target disk, partition, install, reboot
#
# Environment overrides:
#   EZP_TARBALL=<path-or-url>   skip the release lookup (local testing)
#   EZP_ARCH=<amd64|arm64>      force architecture
#   EZP_NO_REBOOT=1             don't reboot/restart when done
set -euo pipefail

REPO="zarigata/EZpenguin"
BOLD='\033[1;36m'; YEL='\033[1;33m'; RED='\033[1;31m'; RST='\033[0m'
say() { printf "%b\n" "$*"; }
die() { printf "%b\n" "${RED}ERROR:${RST} $*" >&2; exit 1; }

banner() {
    printf '%b\n' "${BOLD}
        .--.
       |o_o |
       |:_/ |
      //   \ \\
     (|     | )
    /\"\_   _/\`\\
    \\___)=(___/
     E Z P E N G U I N — online installer${RST}"
}

[[ $EUID -eq 0 ]] || die "run as root"
for cmd in curl tar xz; do command -v "$cmd" >/dev/null || die "missing tool: $cmd"; done

# ---------------------------------------------------------------- detect ----
IN_DOCKER=0
[[ -f /.dockerenv || -f /run/.containerenv ]] && IN_DOCKER=1
grep -qsE 'docker|containerd|kubepods' /proc/1/cgroup 2>/dev/null && IN_DOCKER=1

# idempotent: already converted? (container restart re-runs this installer
# when it was the container command — become a keep-alive instead)
if [[ -f /etc/ezpenguin/.install-source ]] && grep -q '^ID=ezpenguin' /etc/os-release 2>/dev/null; then
    . /etc/os-release
    say "already EZpenguin ($PRETTY_NAME) — nothing to install."
    if [[ "$IN_DOCKER" == 1 ]]; then
        say "keeping container alive (PID1). use: docker exec -it <ctr> bash"
        exec sleep infinity
    fi
    exit 0
fi

banner

ARCH="${EZP_ARCH:-$(uname -m)}"
case "$ARCH" in
    x86_64|amd64) ARCH=amd64 ;;
    aarch64|arm64) ARCH=arm64 ;;
    *) die "unsupported architecture: $ARCH" ;;
esac
say "architecture: ${BOLD}$ARCH${RST}  environment: ${BOLD}$([[ $IN_DOCKER = 1 ]] && echo container || echo host)${RST}"

# ------------------------------------------------------------- download ----
TMPDIR_EZP=$(mktemp -d)
TARBALL="${EZP_TARBALL:-}"

if [[ -z "$TARBALL" ]]; then
    say "locating latest release..."
    REL_JSON="$TMPDIR_EZP/release.json"
    curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" -o "$REL_JSON"
    TAG=$(grep -o '"tag_name": *"[^"]*"' "$REL_JSON" | head -1 | cut -d'"' -f4)
    TARBALL_URL=$(grep -o '"browser_download_url": *"[^"]*-'"$ARCH"'-rootfs.tar.xz"' "$REL_JSON" \
        | head -1 | cut -d'"' -f4)
    [[ -n "$TARBALL_URL" ]] || die "no rootfs asset found for $ARCH in latest release"
    TARBALL="$TMPDIR_EZP/ezpenguin-rootfs.tar.xz"
    say "downloading: ${TARBALL_URL}"
    say "             (tag ${BOLD}${TAG:-?}${RST})"
    curl -fSL --progress-bar -o "$TARBALL" "$TARBALL_URL"
else
    if [[ "$TARBALL" =~ ^https?:// ]]; then
        dl_tmp="$TMPDIR_EZP/ezpenguin-rootfs.tar.xz"
        curl -fSL --progress-bar -o "$dl_tmp" "$TARBALL"; TARBALL="$dl_tmp"
    fi
    [[ -s "$TARBALL" ]] || die "tarball not found: $TARBALL"
fi
say "download OK: $(du -h "$TARBALL" | cut -f1)"

# ------------------------------------------------------- in-place mode -----
inplace_install() {
    say "${YEL}IN-PLACE CONVERSION${RST} — this replaces the running system userland."

    # preserve container DNS + hostname
    cp -a /etc/resolv.conf "$TMPDIR_EZP/resolv.conf" 2>/dev/null || cp /etc/resolv.conf "$TMPDIR_EZP/resolv.conf"
    cp -a /etc/hostname   "$TMPDIR_EZP/hostname"    2>/dev/null || true

    cd /
    say "extracting EZpenguin over /  (a few minutes)"
    # exclusions:
    #  - virtual FS dirs (mounts — read-only or busy)
    #  - /etc/hostname /etc/hosts /etc/resolv.conf (docker bind-mounts them)
    tar -xJf "$TARBALL" -C / --numeric-owner \
        --exclude='./dev' --exclude='./proc' --exclude='./sys' --exclude='./run' \
        --exclude='./dev/*' --exclude='./proc/*' --exclude='./sys/*' --exclude='./run/*' \
        --exclude='./etc/hostname' --exclude='./etc/hosts' --exclude='./etc/resolv.conf' \
        || [[ $? -eq 1 && -f /usr/local/bin/ez-firstboot ]] || die "tar extraction failed"

    # container-friendly fixes
    cp "$TMPDIR_EZP/resolv.conf" /etc/resolv.conf 2>/dev/null || \
        printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf
    cp "$TMPDIR_EZP/hostname" /etc/hostname 2>/dev/null || true
    HN=$(cat /etc/hostname 2>/dev/null || echo ezpenguin)
    printf '127.0.0.1\tlocalhost\n127.0.1.1\t%s\n' "$HN" > /etc/hosts

    # no fstab mounts in a container; avoid systemd emergency on systemd-enabled boots
    printf '# EZpenguin (container install — no local mounts)\n' > /etc/fstab

    # fresh identity + first-boot on next start
    rm -f /etc/machine-id; : > /etc/machine-id
    rm -f /etc/ezpenguin/.configured
    printf 'online-installer %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > /etc/ezpenguin/.install-source

    # clear apt lists (stale from build container? tarball ships clean — cheap safety)
    rm -rf /var/lib/apt/lists/* 2>/dev/null || true

    # hotpatch: banner.sh tty-detection deadlock in 0.4.0 tarballs (fixed upstream)
    sed -i "s/ || grep -aq 'console' [^ ]*//" /usr/local/lib/ezpenguin/banner.sh 2>/dev/null || true

    say ""
    say "${BOLD}Conversion complete — this system is now EZpenguin.${RST}"
    . /etc/os-release 2>/dev/null && say "os-release: $PRETTY_NAME"
    say ""
}

# -------------------------------------------------------- bare metal -------
disk_install() {
    say "${YEL}BARE-METAL INSTALL${RST}"
    lsblk -dnpo NAME,SIZE,MODEL,TYPE | awk '$4=="disk"{print "  " $1 "  " $2 "  " $3}' >&2
    read -r -p "Target disk (e.g. /dev/sda — WILL BE ERASED): " TARGET_DISK
    [[ -b "$TARGET_DISK" ]] || die "not a block device: $TARGET_DISK"
    read -r -p "Type 'YES' to wipe $TARGET_DISK: " CONF
    [[ "$CONF" == YES ]] || die "aborted"

    command -v sgdisk >/dev/null || { apt-get update -qq && apt-get install -y -qq gdisk; } || die "install gdisk first"

    swapoff "$TARGET_DISK"* 2>/dev/null || true
    umount "$TARGET_DISK"* 2>/dev/null || true

    if [[ "$ARCH" == "arm64" ]]; then
        sgdisk -Z "$TARGET_DISK"
        sgdisk -n 1:0:+260M -t 1:ef00 -c 1:ESP "$TARGET_DISK"
        sgdisk -n 2:0:0     -t 2:8300 -c 2:root "$TARGET_DISK"
        ESP="${TARGET_DISK}1"; ROOT="${TARGET_DISK}2"
    else
        sgdisk -Z "$TARGET_DISK"
        sgdisk -n 1:0:+1M   -t 1:ef02 -c 1:BIOSBOOT "$TARGET_DISK"
        sgdisk -n 2:0:+260M -t 2:ef00 -c 2:ESP "$TARGET_DISK"
        sgdisk -n 3:0:0     -t 3:8300 -c 3:root "$TARGET_DISK"
        ESP="${TARGET_DISK}2"; ROOT="${TARGET_DISK}3"
    fi
    partprobe "$TARGET_DISK" 2>/dev/null || true; sleep 2
    [[ -e "$ROOT" ]] || ROOT="${TARGET_DISK}p3"; [[ -e "$ESP" ]] || ESP="${TARGET_DISK}p2"

    mkfs.vfat -F32 -n EZP_BOOT "$ESP"
    mkfs.ext4 -L EZP_ROOT -q "$ROOT"

    MNT=$(mktemp -d)
    mount "$ROOT" "$MNT"; mkdir -p "$MNT/boot/efi"; mount "$ESP" "$MNT/boot/efi"
    tar -xJf "$TARBALL" -C "$MNT" --numeric-owner
    printf 'LABEL=EZP_ROOT  /         ext4 defaults,noatime 0 1\nLABEL=EZP_BOOT  /boot/efi vfat defaults 0 2\n' > "$MNT/etc/fstab"
    rm -f "$MNT/etc/machine-id"; : > "$MNT/etc/machine-id"
    rm -f "$MNT/etc/ezpenguin/.configured"
    for d in dev proc sys; do mount --bind "/$d" "$MNT/$d"; done
    ROOT_UUID=$(blkid -s UUID -o value "$ROOT")
    KVER=$(basename "$(ls "$MNT"/boot/vmlinuz-* | sort -V | tail -1)" | sed 's/vmlinuz-//')
    chroot "$MNT" /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin bash -exc '
        if [ "'$ARCH'" = arm64 ]; then
            grub-install --target=arm64-efi --efi-directory=/boot/efi --boot-directory=/boot --no-nvram --removable
        else
            grub-install --target=x86_64-efi --efi-directory=/boot/efi --boot-directory=/boot --no-nvram --removable || true
            grub-install --target=i386-pc --boot-directory=/boot '"$TARGET_DISK"' || true
        fi' >&2
    mkdir -p "$MNT/boot/grub"
    CONSOLE=$([[ "$ARCH" = arm64 ]] && echo 'console=tty0 console=ttyAMA0,115200' || echo 'console=tty0 console=ttyS0,115200n8')
    cat > "$MNT/boot/grub/grub.cfg" <<EOF
set default=0
set timeout=3
menuentry "EZpenguin GNU/Linux" {
    search --no-floppy --fs-uuid --set=root $ROOT_UUID
    linux /boot/vmlinuz-$KVER root=UUID=$ROOT_UUID rw $CONSOLE
    initrd /boot/initrd.img-$KVER
}
EOF
    umount "$MNT/dev" "$MNT/proc" "$MNT/sys" "$MNT/boot/efi" "$MNT"; sync
    say "${BOLD}Installed to $TARGET_DISK — reboot into EZpenguin.${RST}"
}

# ----------------------------------------------------------------- main -----
if [[ "$IN_DOCKER" == 1 || "${EZP_INPLACE:-0}" == 1 ]]; then
    inplace_install
    ACTION="restart this container"
else
    disk_install
    ACTION="reboot"
fi

if [[ "${EZP_NO_REBOOT:-0}" == 1 ]]; then
    say "EZP_NO_REBOOT=1 — skipping $ACTION (run it yourself)"
else
    say "rebooting now: ${BOLD}$ACTION${RST} → boots into EZpenguin, first-boot wizard starts"
    sleep 2
    if [[ "$IN_DOCKER" == 1 ]]; then
        # if this installer IS the container command (PID1), exiting stops the
        # container — the restart policy boots it again into EZpenguin
        # (idempotent guard above turns the re-run into a keep-alive).
        # when run via `docker exec`, signal PID1 as a best effort.
        if [[ $$ -eq 1 ]]; then
            exit 0
        else
            kill -TERM 1 2>/dev/null || kill -KILL 1 2>/dev/null || true
            say "if still running: docker restart <container>"
            exit 0
        fi
    else
        systemctl reboot || reboot || true
    fi
fi
