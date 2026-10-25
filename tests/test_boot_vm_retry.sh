#!/usr/bin/env bash
# test_boot_vm_retry.sh — run boot test with 1 retry.
# TCG emulation (no KVM) has timing races under host load; a single retry
# separates emulator flakiness from real image defects.
# 2 consecutive failures = real failure.
set -uo pipefail

IMG="${1:?img required}"
TIMEOUT="${2:-480}"
FIRMWARE="${3:-bios}"
ARCH="${4:-amd64}"
HERE="$(cd "$(dirname "$0")" && pwd)"

if bash "$HERE/test_boot_vm.sh" "$IMG" "$TIMEOUT" "$FIRMWARE" "$ARCH"; then
    exit 0
fi
echo "# first $FIRMWARE/$ARCH boot attempt failed — retrying once (emulator flakiness guard)"
bash "$HERE/test_boot_vm.sh" "$IMG" "$TIMEOUT" "$FIRMWARE" "$ARCH"
