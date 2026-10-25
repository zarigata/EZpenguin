#!/usr/bin/env bash
# rootfs.sh — build the EZpenguin rootfs. RUNS INSIDE DOCKER (debian env).
# Usage: rootfs.sh <arch> <workspace-dir>
set -euo pipefail

ARCH="${1:?arch required (amd64|arm64)}"
WS="${2:?workspace dir required}"

# shellcheck source=/dev/null
source /build/config/ezpenguin.cfg || source "$WS/config/ezpenguin.cfg"

# rootfs builds into the shared Docker volume (/out) — Linux FS semantics
# (case-sensitive + mknod), impossible on macOS bind mounts.
TARGET="/out/rootfs-$ARCH"
LISTS="$WS/config"
rm -rf "$TARGET"
mkdir -p /out

log() { printf '\033[1;34m[rootfs]\033[0m %s\n' "$*" >&2; }

# ---------------------------------------------------------------- 1. base ---
HOST_ARCH=$(uname -m)
FOREIGN=0
if [[ "$ARCH" == "arm64" && "$HOST_ARCH" != "aarch64" ]]; then
    FOREIGN=1
fi

# qemu interpreter for cross chroot (copied in, removed at the end)
QEMU_STATIC=""
if (( FOREIGN )); then
    # SAFETY: never write binfmt_misc entries ourselves — a malformed
    # registration can wedge the Docker VM's exec path entirely. Require a
    # pre-registered host handler (standard way:
    #   docker run --privileged tonistiigi/binfmt --install arm64)
    # NOTE: mounting the binfmt_misc VIEW is safe; we never write entries.
    mkdir -p /proc/sys/fs/binfmt_misc 2>/dev/null || true
    mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc 2>/dev/null || true
    if [[ ! -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]]; then
        echo "arm64 cross-build needs the qemu-aarch64 binfmt handler." >&2
        echo "register it first:  docker run --privileged tonistiigi/binfmt --install arm64" >&2
        exit 1
    fi
    QEMU_STATIC=$(command -v qemu-aarch64-static 2>/dev/null || \
        find /usr/libexec -name 'qemu-aarch64-static' 2>/dev/null | head -1 || true)
    [[ -n "$QEMU_STATIC" ]] || { echo "qemu-aarch64-static missing" >&2; exit 1; }
    log "binfmt qemu-aarch64 handler present — transparent cross chroot"
fi

log "debootstrap $EZP_SUITE ($ARCH) — this downloads ~150 packages"
if (( FOREIGN )); then
    debootstrap \
        --arch="$ARCH" --foreign \
        --variant=minbase \
        --include=ca-certificates \
        "$EZP_SUITE" "$TARGET" "$EZP_MIRROR"
    log "foreign stage 2 (under qemu-user)"
    install -D -m 755 "$QEMU_STATIC" "$TARGET/usr/bin/qemu-aarch64-static"
    chroot "$TARGET" /debootstrap/debootstrap --second-stage
else
    debootstrap \
        --arch="$ARCH" \
        --variant=minbase \
        --include=ca-certificates \
        "$EZP_SUITE" "$TARGET" "$EZP_MIRROR"
fi

# --------------------------------------------------------- 2. chroot prep ---
log "preparing chroot"
mount -t proc proc "$TARGET/proc" 2>/dev/null || true
mount --bind /dev "$TARGET/dev" 2>/dev/null || true
mount --bind /dev/pts "$TARGET/dev/pts" 2>/dev/null || true
cleanup() {
    umount "$TARGET/dev/pts" 2>/dev/null || true
    umount "$TARGET/dev" 2>/dev/null || true
    umount "$TARGET/proc" 2>/dev/null || true
}
trap cleanup EXIT

chroot_run() {
    chroot "$TARGET" /usr/bin/env -i \
        HOME=/root PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        TERM="${TERM:-dumb}" DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
        LANG=C.UTF-8 /bin/bash -e -c "$*"
}

# ------------------------------------------------------ 3. apt sources ------
log "writing APT sources"
cat > "$TARGET/etc/apt/sources.list" <<EOF
deb $EZP_MIRROR $EZP_SUITE main contrib non-free non-free-firmware
deb $EZP_MIRROR $EZP_SUITE-updates main contrib non-free non-free-firmware
deb $EZP_SECURITY_MIRROR $EZP_SUITE-security main contrib non-free non-free-firmware
EOF

chroot_run 'apt-get update'

# ------------------------------------------------------ 4. packages ---------
# strip inline comments too — otherwise '#' truncates the install line in shell
PKGS=$(sed -E 's/#.*$//' "$LISTS/packages-base.list" | grep -Ev '^\s*$' | tr '\n' ' ')

# arch-specific kernel/bootloader handled per-target
if [[ "$ARCH" == "arm64" ]]; then
    PKGS=$(sed -e 's/linux-image-amd64/linux-image-arm64/' \
                -e 's/grub-efi-amd64/grub-efi-arm64/' \
                -e 's/grub-pc-bin//' \
                -e 's/grub2-common/grub-efi-arm64 grub2-common/' <<< "$PKGS")
fi

log "installing base packages ($(wc -w <<< "$PKGS") pkgs)"
chroot_run "apt-get install -y --no-install-recommends $PKGS"

EXCL=$(sed -E 's/#.*$//' "$LISTS/packages-exclude.list" | grep -Ev '^\s*$' | tr '\n' ' ' || true)
if [[ -n "${EXCL// /}" ]]; then
    log "excluding packages"
    chroot_run "apt-get purge -y $EXCL || true"
fi

chroot_run 'apt-get autoremove -y --purge'
chroot_run 'apt-get clean'

# ------------------------------------------------------- 5. overlay ---------
log "applying rootfs overlay"
if [[ -d "$WS/rootfs-overlay" ]]; then
    cp -a "$WS/rootfs-overlay/." "$TARGET/"
fi

# preserve executability of scripts
[[ -f "$TARGET/usr/local/bin/ez-firstboot" ]] && chmod 755 "$TARGET/usr/local/bin/ez-firstboot"
for f in "$TARGET"/usr/local/bin/ez-*; do [[ -f "$f" ]] && chmod 755 "$f"; done
for f in "$TARGET"/usr/local/sbin/ez-*; do [[ -f "$f" ]] && chmod 755 "$f"; done

# ------------------------------------------------ 6. identity stamping ------
log "stamping identity"
install -d "$TARGET/etc/ezpenguin"
printf '%s\n' "$EZP_VERSION" > "$TARGET/etc/ezpenguin/version"
printf '%s\n' "$EZP_NAME $EZP_VERSION ($EZP_SUITE/$ARCH)" > "$TARGET/etc/ezpenguin/pretty-name"
printf '%s\n' "$ARCH" > "$TARGET/etc/ezpenguin/arch"

cat > "$TARGET/etc/os-release" <<EOF
PRETTY_NAME="$EZP_NAME $EZP_VERSION"
NAME="$EZP_NAME"
VERSION_ID="$EZP_VERSION"
VERSION="$EZP_VERSION ($EZP_SUITE)"
ID=ezpenguin
ID_LIKE=debian
HOME_URL="https://ezpenguin.org"
SUPPORT_URL="https://ezpenguin.org/support"
BUG_REPORT_URL="https://ezpenguin.org/bugs"
EOF
ln -sf os-release "$TARGET/etc/lsb-release" 2>/dev/null || true

echo "ezpenguin" > "$TARGET/etc/hostname"

# ------------------------------------------------ 7. system polish ----------
log "system polish"
chroot_run 'systemctl enable ezpenguin-firstboot.service 2>/dev/null || true'
chroot_run 'systemctl disable ssh 2>/dev/null || true'
# networking via systemd-networkd (robust with predictable iface names)
chroot_run 'systemctl enable systemd-networkd.service systemd-resolved.service 2>/dev/null || true'
chroot_run 'ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf 2>/dev/null || true'

# default target: text console (fast, server-like; wizard is TUI)
chroot_run 'systemctl set-default multi-user.target'

# ------------------------------------------------------- 7. slimming --------
log "slimming: locales, docs, man (DietPi-style)"
if [[ -d "$TARGET/usr/share/locale" ]]; then
    ( cd "$TARGET/usr/share/locale"
      for d in *; do
          case "$d" in
              en|en_US|en_GB|pt|pt_BR|es|de|fr|it|locale|locale_alias) ;; # keep
              *) rm -rf "$d" ;;
          esac
      done )
fi
rm -rf "$TARGET/usr/share/doc"/* "$TARGET/usr/share/man"/* 2>/dev/null || true
mkdir -p "$TARGET/usr/share/doc" "$TARGET/usr/share/man"

# no machine-id → cloned image regenerates it on first boot
rm -f "$TARGET/etc/machine-id"
touch "$TARGET/etc/machine-id"

# cross-build helper no longer needed inside the artifact
rm -f "$TARGET/usr/bin/qemu-aarch64-static"

# apt cache/logs/tmp cleanup
rm -rf "$TARGET/var/lib/apt/lists/"* "$TARGET/var/cache/apt/"*
rm -rf "$TARGET/tmp/"* "$TARGET/var/tmp/"*
find "$TARGET/var/log" -type f -exec truncate -s 0 {} \;

log "rootfs complete: $TARGET"
du -sh "$TARGET" >&2 || true
