#!/usr/bin/env bash
# test_iso_boot.sh — boot the EZpenguin live ISO in QEMU and verify it
# reaches the first-boot wizard in live mode. RUNS INSIDE DOCKER.
# Usage: test_iso_boot.sh <iso-file> [timeout-seconds] [bios|uefi]
set -uo pipefail

ISO="${1:?iso required}"
TIMEOUT="${2:-600}"
FIRMWARE="${3:-bios}"

LOG="$(mktemp)"
QEMU=/usr/bin/qemu-system-x86_64
FIRMWARE_ARGS=()

if [[ "$FIRMWARE" == "uefi" ]]; then
    OVMF=/usr/share/OVMF/OVMF_CODE.fd
    [[ -f "$OVMF" ]] || OVMF=$(find /usr/share -name 'OVMF_CODE*.fd' 2>/dev/null | head -1)
    [[ -f "$OVMF" ]] || { echo "not ok 1 - OVMF firmware not found"; exit 1; }
    FIRMWARE_ARGS=(-bios "$OVMF")
fi

echo "# ISO boot test ($FIRMWARE): $ISO (timeout ${TIMEOUT}s)"

"$QEMU" \
    -m 1536 -smp 1 \
    "${FIRMWARE_ARGS[@]}" \
    -cdrom "$ISO" \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
    -nographic -no-reboot \
    -serial mon:stdio \
    -display none \
    >"$LOG" 2>&1 &
QPID=$!

cleanup() { kill "$QPID" 2>/dev/null; wait "$QPID" 2>/dev/null; }
trap cleanup EXIT

# live boot markers:
#  - squashfs mounted = live userspace assembled
#  - "First-Boot Wizard" service started (systemd unit name on serial)
#  - login prompt = full multi-user boot reached
LIVE_OK=0
WIZARD_OK=0
LOGIN_OK=0
for ((i=0; i<TIMEOUT; i+=2)); do
    if (( ! LIVE_OK )) && grep -q 'filesystem.squashfs' "$LOG" 2>/dev/null; then
        LIVE_OK=1
        echo "# live root mounted (squashfs)"
    fi
    if (( ! WIZARD_OK )) && grep -q 'First-Boot Wizard' "$LOG" 2>/dev/null; then
        WIZARD_OK=1
        echo "# first-boot wizard service started"
    fi
    if (( ! LOGIN_OK )) && grep -q 'ezpenguin login:' "$LOG" 2>/dev/null; then
        LOGIN_OK=1
        echo "# multi-user target reached (login prompt)"
    fi
    if (( LIVE_OK && WIZARD_OK && LOGIN_OK )); then
        break
    fi
    kill -0 "$QPID" 2>/dev/null || break
    sleep 2
done

echo "----- last 25 lines of serial console -----"
tail -25 "$LOG" | cat -v
echo "-------------------------------------------"

cp "$LOG" "/out/iso-${FIRMWARE}-serial.log" 2>/dev/null || true

RC=0
if (( WIZARD_OK )); then
    echo "ok 1 - iso($FIRMWARE) booted live, first-boot wizard service started"
else
    echo "not ok 1 - iso($FIRMWARE) wizard service not observed within ${TIMEOUT}s"
    RC=1
fi
if (( LIVE_OK && LOGIN_OK )); then
    echo "ok 2 - iso($FIRMWARE) live root mounted, multi-user reached"
else
    echo "not ok 2 - iso($FIRMWARE) live mount/multi-user not confirmed"
    RC=1
fi
exit $RC
