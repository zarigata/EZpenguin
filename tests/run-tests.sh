#!/usr/bin/env bash
# run-tests.sh — EZpenguin QA suite. RUNS INSIDE DOCKER against a rootfs.
# Usage: run-tests.sh <rootfs-dir> [arch]
set -uo pipefail

ROOTFS="${1:?rootfs dir required}"
ARCH="${2:-amd64}"
HERE="$(cd "$(dirname "$0")" && pwd)"

PASS=0; FAIL=0; FAILED=()

t() { # t "name" cmd...  (use `bash -c '!'` for negation — `!` is a keyword)
    local name="$1"; shift
    if "$@" >/dev/null 2>&1; then
        PASS=$((PASS+1)); echo "ok $PASS - $name"
    else
        FAIL=$((FAIL+1)); echo "not ok $PASS - $name"
        FAILED+=("$name")
    fi
}

# exists: file/dir/symlink — absolute symlinks inside rootfs can't be
# followed from outside the chroot, so a dangling-looking link is still valid
exists() { [ -e "$1" ] || [ -L "$1" ]; }

chr() { # run in chroot quietly
    chroot "$ROOTFS" /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin /bin/bash -e -c "$*" 2>/dev/null
}

echo "TAP version 13"
echo "# rootfs: $ROOTFS ($ARCH)"
echo

# ============================================================ L1 structure ==
echo "# L1: structure"
for f in \
    /etc/ezpenguin/version /etc/os-release /etc/hostname /etc/fstab \
    /usr/local/bin/ez-firstboot /usr/local/bin/ez-info \
    /usr/local/bin/ez-update /usr/local/bin/ez-config \
    /usr/local/bin/ez-doctor /usr/local/bin/ez-net \
    /usr/local/sbin/ez-install \
    /etc/systemd/system/ezpenguin-firstboot.service \
    /etc/apt/sources.list /bin/sh /etc/passwd /etc/shadow /etc/sudoers; do
    t "L1 file exists: $f" exists "$ROOTFS$f"
done
t "L1 identity dir"           test -d "$ROOTFS/etc/ezpenguin"
t "L1 version non-empty"      test -s "$ROOTFS/etc/ezpenguin/version"
t "L1 firstboot executable"   test -x "$ROOTFS/usr/local/bin/ez-firstboot"
t "L1 ez-info executable"     test -x "$ROOTFS/usr/local/bin/ez-info"
t "L1 os-release has ID"      grep -q 'ID=ezpenguin' "$ROOTFS/etc/os-release"
t "L1 hostname is set"        test -s "$ROOTFS/etc/hostname"
t "L1 apt sources configured" grep -q 'debian.org' "$ROOTFS/etc/apt/sources.list"

# ============================================================ L2 packages ===
echo
echo "# L2: packages"
t "L2 dpkg audit clean"       chr 'dpkg --audit | grep -q . && exit 1 || exit 0'
t "L2 apt check (deps ok)"    chr 'apt-get check'

BASE_LIST="$HERE/../config/packages-base.list"
while IFS= read -r pkg; do
    pkg="${pkg%%#*}"; pkg="${pkg// /}"; pkg="${pkg//$'\t'/}"
    case "$pkg" in ''|*[!a-zA-Z0-9.+-]*) [[ "$pkg" =~ ^[a-zA-Z0-9][a-zA-Z0-9.+-]*$ ]] || continue ;; esac
    # mirror rootfs.sh arch mapping
    if [[ "$ARCH" == "arm64" ]]; then
        case "$pkg" in
            linux-image-amd64)   pkg=linux-image-arm64 ;;
            grub-efi-amd64-bin)  pkg=grub-efi-arm64-bin ;;
            grub-pc-bin)         continue ;;  # BIOS grub: amd64-only
        esac
    fi
    t "L2 installed: $pkg" chr "dpkg -s '$pkg' >/dev/null 2>&1"
done < "$BASE_LIST"

EXCL_LIST="$HERE/../config/packages-exclude.list"
while IFS= read -r pkg; do
    pkg="${pkg%%#*}"; pkg="${pkg// /}"; pkg="${pkg//$'\t'/}"
    [[ "$pkg" =~ ^[a-zA-Z0-9][a-zA-Z0-9.+-]*$ ]] || continue
    t "L2 excluded: $pkg" chr "dpkg -s '$pkg' >/dev/null 2>&1 && exit 1 || exit 0"
done < "$EXCL_LIST"

# ============================================================ L3 runtime ====
echo
echo "# L3: runtime"
t "L3 systemd is init"        chr 'test -x /usr/bin/systemd || test -x /usr/lib/systemd/systemd'
t "L3 systemd dir"            test -d "$ROOTFS/etc/systemd/system"
t "L3 kernel installed"       chr 'test -n "$(ls /boot/vmlinuz-* 2>/dev/null)"'
t "L3 initramfs present"      chr 'test -n "$(ls /boot/initrd.img-* 2>/dev/null)"'
t "L3 grub present"           chr 'which grub-install >/dev/null 2>&1 || test -x /usr/sbin/grub-install'
t "L3 firstboot syntax"       bash -n "$ROOTFS/usr/local/bin/ez-firstboot"
t "L3 ez-info syntax"         bash -n "$ROOTFS/usr/local/bin/ez-info"
t "L3 ez-update syntax"       bash -n "$ROOTFS/usr/local/bin/ez-update"
t "L3 ez-config syntax"       bash -n "$ROOTFS/usr/local/bin/ez-config"
t "L3 ez-doctor syntax"       bash -n "$ROOTFS/usr/local/bin/ez-doctor"
t "L3 ez-net syntax"          bash -n "$ROOTFS/usr/local/bin/ez-net"
t "L3 ez-install syntax"      bash -n "$ROOTFS/usr/local/sbin/ez-install"
t "L3 ez-doctor executable"   test -x "$ROOTFS/usr/local/bin/ez-doctor"
t "L3 ez-net executable"      test -x "$ROOTFS/usr/local/bin/ez-net"
t "L3 ez-install executable"  test -x "$ROOTFS/usr/local/sbin/ez-install"
t "L3 live-boot present"      chr 'dpkg -s live-boot >/dev/null 2>&1'
t "L3 timeout hardening"      exists "$ROOTFS/etc/systemd/system.conf.d/10-timeouts.conf"
t "L3 os-release version"     grep -q "VERSION_ID=" "$ROOTFS/etc/os-release"
t "L3 wizard live-mode aware" grep -q 'boot=live' "$ROOTFS/usr/local/bin/ez-firstboot"
t "L3 unit is valid"          chr 'systemd-analyze verify /etc/systemd/system/ezpenguin-firstboot.service 2>/dev/null || systemd-analyze verify /etc/systemd/system/ezpenguin-firstboot.service'
t "L3 firstboot enabled"      exists "$ROOTFS/etc/systemd/system/multi-user.target.wants/ezpenguin-firstboot.service"
t "L3 shadow: root locked"    chr 'getent shadow root | cut -d: -f2 | grep -q "^\!" || getent shadow root | cut -d: -f2 | grep -q "^\*"'
t "L3 shadow: no empty pass"  bash -c "! grep -qE '^[^:]+::' '$ROOTFS/etc/shadow'"
t "L3 machine-id empty"       bash -c "! test -s '$ROOTFS/etc/machine-id'"
t "L3 sudo installed"         chr 'which sudo >/dev/null 2>&1'
t "L3 ssh present, default off" test ! -e "$ROOTFS/etc/systemd/system/multi-user.target.wants/ssh.service" -o ! -e "$ROOTFS/etc/systemd/system/multi-user.target.wants/sshd.service"

# ============================================================ L4 size =======
echo
echo "# L4: budget"
SIZE_MB=$(du -sm --apparent-size "$ROOTFS" 2>/dev/null | cut -f1)
MAX_MB=$(grep -oP 'EZP_MAX_ROOTFS_MB="\K[0-9]+' "$HERE/../config/ezpenguin.cfg" || echo 450)
t "L4 rootfs size ${SIZE_MB}MB <= ${MAX_MB}MB" test "$SIZE_MB" -le "$MAX_MB"
echo "  # rootfs size: ${SIZE_MB}MB"

# ============================================================ summary =======
echo
echo "1..$((PASS+FAIL))"
echo "# pass=$PASS fail=$FAIL"
if (( FAIL > 0 )); then
    echo "# FAILED tests:"
    for f in "${FAILED[@]}"; do echo "#   - $f"; done
    exit 1
fi
echo "# ALL TESTS PASSED"
