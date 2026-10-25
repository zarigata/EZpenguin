#!/usr/bin/env bash
# test_boot_vm.sh — boot EZpenguin IMG in QEMU and verify it reaches the
# first-boot wizard. RUNS INSIDE DOCKER (privileged).
# Usage: test_boot_vm.sh <img-file> [timeout-seconds] [bios|uefi] [arch]
set -uo pipefail

IMG="${1:?img required}"
TIMEOUT="${2:-240}"
FIRMWARE="${3:-bios}"
ARCH="${4:-amd64}"

LOG="$(mktemp)"
FIRMWARE_ARGS=()
MACHINE_ARGS=(-m 1024 -smp 1)

if [[ "$ARCH" == "arm64" ]]; then
    QEMU=/usr/bin/qemu-system-aarch64
    [[ -x "$QEMU" ]] || { echo "not ok 1 - qemu-system-aarch64 not installed"; exit 1; }
    MACHINE_ARGS+=(-M virt -cpu cortex-a57)
    if [[ "$FIRMWARE" == "uefi" ]]; then
        OVMF=/usr/share/AAVMF/AAVMF_CODE.fd
        [[ -f "$OVMF" ]] || OVMF=$(find /usr/share -name 'AAVMF_CODE*.fd' 2>/dev/null | head -1)
        [[ -f "$OVMF" ]] || { echo "not ok 1 - AAVMF firmware not found"; exit 1; }
        FIRMWARE_ARGS=(-bios "$OVMF")
    else
        echo "not ok 1 - arm64 requires UEFI firmware (BIOS not supported)"; exit 1
    fi
else
    QEMU=/usr/bin/qemu-system-x86_64
    if [[ "$FIRMWARE" == "uefi" ]]; then
        OVMF=/usr/share/OVMF/OVMF_CODE.fd
        [[ -f "$OVMF" ]] || OVMF=$(find /usr/share -name 'OVMF_CODE*.fd' 2>/dev/null | head -1)
        [[ -f "$OVMF" ]] || { echo "not ok 1 - OVMF firmware not found"; exit 1; }
        FIRMWARE_ARGS=(-bios "$OVMF")
    fi
fi

echo "# boot test ($FIRMWARE/$ARCH): $IMG (timeout ${TIMEOUT}s)"

"$QEMU" \
    "${MACHINE_ARGS[@]}" \
    "${FIRMWARE_ARGS[@]}" \
    -drive file="$IMG",format=raw,if=virtio \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
    -nographic -no-reboot \
    -serial mon:stdio \
    -display none \
    >"$LOG" 2>&1 &
QPID=$!

cleanup() { kill "$QPID" 2>/dev/null; wait "$QPID" 2>/dev/null; }
trap cleanup EXIT

MARK_OK=0
for ((i=0; i<TIMEOUT; i+=2)); do
    if grep -q 'ez-firstboot\|EZpenguin First-Boot\|EZ  •  PENGUIN\|Welcome to EZpenguin\|live mode detected' "$LOG" 2>/dev/null; then
        MARK_OK=1
        break
    fi
    kill -0 "$QPID" 2>/dev/null || break
    sleep 2
done

echo "----- last 25 lines of serial console -----"
tail -25 "$LOG" | cat -v
echo "-------------------------------------------"

# persist full serial log for post-mortem (mounted volume)
cp "$LOG" "/out/boot-${FIRMWARE}-${ARCH}-serial.log" 2>/dev/null || true

if (( MARK_OK )); then
    echo "ok 1 - boot($FIRMWARE/$ARCH) reached EZpenguin first-boot wizard"
    exit 0
else
    echo "not ok 1 - boot($FIRMWARE/$ARCH) did NOT reach first-boot wizard within ${TIMEOUT}s"
    echo "# full serial log: $LOG"
    exit 1
fi
