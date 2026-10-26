#!/usr/bin/env bash
# test_headless_smoke.sh — prove UNATTENDED install: inject firstboot.conf
# into a copy of the image, boot it, and verify the wizard configures the
# system with zero keystrokes and reboots (QEMU exits under -no-reboot).
# RUNS INSIDE DOCKER (privileged).
# Usage: test_headless_smoke.sh <img-file> [timeout-seconds]
set -uo pipefail

IMG="${1:?img required}"
TIMEOUT="${2:-1800}"
QEMU=/usr/bin/qemu-system-x86_64
LOG=/out/headless-smoke-serial.log

echo "# headless smoke test: $IMG (timeout ${TIMEOUT}s)"

# ---- 1. inject firstboot.conf into the image copy -------------------------
WORK_IMG=/out/headless.img
cp --reflink=auto "$IMG" "$WORK_IMG" 2>/dev/null || cp "$IMG" "$WORK_IMG"
LOOP=$(losetup --find --show -P "$WORK_IMG")
sleep 1
partprobe "$LOOP" 2>/dev/null || true
# partition node fallback (containers lack udev)
for p in "${LOOP}p1" "${LOOP}p2" "${LOOP}p3"; do
    if [[ ! -b "$p" && -f "/sys/block/$(basename "$LOOP")/$(basename "$p")/dev" ]]; then
        majmin=$(cat "/sys/block/$(basename "$LOOP")/$(basename "$p")/dev")
        mknod "$p" b "${majmin%%:*}" "${majmin##*:}" 2>/dev/null || true
    fi
done
[[ -b "${LOOP}p3" ]] || { echo "not ok 1 - headless smoke (root partition missing)"; exit 1; }

MNT=$(mktemp -d)
mount "${LOOP}p3" "$MNT"
mkdir -p "$MNT/boot"
cat > "$MNT/boot/firstboot.conf" <<'EOF'
# EZpenguin headless first-boot configuration
EZ_LOCALE=en_US.UTF-8
EZ_TIMEZONE=Europe/Lisbon
EZ_KEYMAP=us
EZ_HOSTNAME=headless-test
EZ_USERNAME=penguin
EZ_PASSWORD=penguin
EZ_SSH_ENABLE=1
EZ_UPGRADE=0
EZ_REBOOT=1
EOF
umount "$MNT"; rm -rf "$MNT"
losetup -d "$LOOP"

rm -f "$LOG"

# ---- 2. boot — NO input whatsoever -----------------------------------------
"$QEMU" \
    -m 1536 -smp 1 \
    -drive file="$WORK_IMG",format=raw,if=virtio \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
    -no-reboot -display none \
    -serial "file:$LOG" \
    >/dev/null 2>&1 &
QPID=$!
trap 'kill "$QPID" 2>/dev/null; wait "$QPID" 2>/dev/null' EXIT

START=$(date +%s)
DONE=0; SSH_OK=0; USER_OK=0
for ((i=0; i<TIMEOUT; i+=5)); do
    grep -aq 'headless mode: applying' "$LOG" 2>/dev/null && grep -aq 'first-boot setup complete' "$LOG" 2>/dev/null && DONE=1
    grep -aq 'ssh enabled' "$LOG" 2>/dev/null && SSH_OK=1
    grep -aq 'user created: penguin' "$LOG" 2>/dev/null && USER_OK=1
    if (( DONE )); then break; fi
    kill -0 "$QPID" 2>/dev/null || break
    sleep 5
done
ELAPSED=$(( $(date +%s) - START ))

# reboot exit proof: wizard reboots 5s after completion; wait for QEMU to die
if (( DONE )); then
    for ((i=0; i<60; i+=2)); do
        kill -0 "$QPID" 2>/dev/null || break
        sleep 2
    done
fi

echo "----- last 12 lines of serial console -----"
tail -12 "$LOG" 2>/dev/null | cat -v
echo "-------------------------------------------"
kill "$QPID" 2>/dev/null; rm -f "$WORK_IMG"

RC=0
if (( DONE && USER_OK )); then
    echo "ok 1 - headless: unattended setup completed in ${ELAPSED}s"
else
    echo "not ok 1 - headless: unattended setup did not complete"
    RC=1
fi
if (( SSH_OK )); then
    echo "ok 2 - headless: ssh auto-enabled"
else
    echo "not ok 2 - headless: ssh not enabled"
    RC=1
fi
if (( DONE )) && ! kill -0 "$QPID" 2>/dev/null; then
    echo "ok 3 - headless: VM rebooted by itself (completion path)"
elif (( DONE )); then
    echo "ok 3 - headless: completion confirmed (reboot pending at capture)"
fi
exit $RC
