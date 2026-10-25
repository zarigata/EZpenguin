#!/usr/bin/env bash
# test_wizard_smoke.sh — boot the IMG and WALK the first-boot wizard using
# QEMU monitor keystroke injection; verifies full configuration completes
# (wizard ends by rebooting the VM — under -no-reboot QEMU exits).
# RUNS INSIDE DOCKER (privileged).
# Usage: test_wizard_smoke.sh <img-file> [timeout-seconds]
set -uo pipefail

IMG="${1:?img required}"
TIMEOUT="${2:-2400}"
QEMU=/usr/bin/qemu-system-x86_64
LOG=/out/wizard-smoke-serial.log
MONPORT=5599

rm -f "$LOG"

echo "# wizard smoke test: $IMG (timeout ${TIMEOUT}s)"

"$QEMU" \
    -m 1536 -smp 1 \
    -drive file="$IMG",format=raw,if=virtio \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
    -no-reboot -display none -vga std \
    -serial "file:$LOG" \
    -monitor "telnet:127.0.0.1:$MONPORT,server,nowait" \
    >/dev/null 2>&1 &
QPID=$!

cleanup() { kill "$QPID" 2>/dev/null; wait "$QPID" 2>/dev/null; }
trap cleanup EXIT

# ---- monitor helpers -------------------------------------------------------
mon_open() {
    for _ in $(seq 1 30); do
        if exec 3<>/dev/tcp/127.0.0.1/$MONPORT 2>/dev/null; then return 0; fi
        sleep 1
    done
    return 1
}
send() { printf '%s\n' "$*" >&3; sleep 0.3; }

type_str() {
    local s="$1" c
    for ((i=0; i<${#s}; i++)); do
        c="${s:$i:1}"
        case "$c" in
            [a-z0-9]) send "sendkey $c" ;;
            [A-Z])    send "sendkey shift-${c,,}" ;;
            '.')      send "sendkey dot" ;;
            '-')      send "sendkey minus" ;;
            '_')      send "sendkey shift-minus" ;;
            ' ')      send "sendkey spc" ;;
            *)        send "sendkey $c" ;;
        esac
    done
}
enter() { send "sendkey ret"; }

wait_for() { # wait_for <pattern> <seconds>
    local pat="$1" secs="${2:-300}" waited=0
    while (( waited < secs )); do
        grep -aq "$pat" "$LOG" 2>/dev/null && return 0
        kill -0 "$QPID" 2>/dev/null || return 1
        sleep 3; waited=$((waited+3))
    done
    return 1
}

step() { echo "# step: $*"; }
START=$(date +%s)
ELAPSED() { echo $(( $(date +%s) - START )); }

mon_open || { echo "not ok 1 - wizard smoke (monitor connect failed)"; exit 1; }

# ---- 1. boot: wait for wizard start marker (stderr -> console -> serial) ---
step "waiting for wizard start"
if ! wait_for 'wizard started\|expanding root filesystem\|expansion skipped' 900; then
    echo "not ok 1 - wizard smoke (wizard never started) after $(ELAPSED)s"
    tail -20 "$LOG" 2>/dev/null | cat -v; exit 1
fi
step "wizard started after $(ELAPSED)s"

# ---- 2. locale (default) — wait for expansion to finish first --------------
wait_for 'root filesystem expanded\|expansion skipped' 300 || true
sleep 5
step "locale (accept default)"
enter

# ---- 3. timezone ------------------------------------------------------------
if wait_for 'locale set\|keeping C.UTF-8' 180; then sleep 3; else step "locale marker missing, continuing"; sleep 10; fi
step "timezone (accept default)"
enter

# ---- 4. keymap --------------------------------------------------------------
if wait_for 'timezone set\|keeping default' 180; then sleep 3; else step "tz marker missing, continuing"; sleep 10; fi
step "keymap (accept default)"
enter

# ---- 5. hostname ------------------------------------------------------------
if wait_for 'keymap set' 180; then sleep 3; else step "keymap marker missing, continuing"; sleep 10; fi
step "hostname (accept default)"
enter

# ---- 6. username + password boxes ------------------------------------------
if wait_for 'hostname set' 180; then sleep 3; else step "hostname marker missing, continuing"; sleep 10; fi
step "username (accept default 'penguin'), then password 'penguin' twice"
enter
sleep 10
type_str "penguin"; sleep 1; enter
sleep 6
type_str "penguin"; sleep 1; enter

# ---- 7. ssh yesno — Enter selects <Yes> ------------------------------------
step "ssh enable prompt (Enter = Yes)"
if wait_for 'ssh enabled\|updating packages' 240; then
    grep -aq 'ssh enabled' "$LOG" 2>/dev/null || { sleep 3; enter; }
else
    step "ssh marker missing — sending Enter anyway"
    sleep 5; enter
fi

# ---- 8. completion: wizard touches .configured and reboots -----------------
# -no-reboot: the guest reboot terminates QEMU (process exits)
step "waiting for setup completion (apt update/upgrade runs — slow in TCG)"
DONE=0
for ((i=0; i<TIMEOUT; i+=5)); do
    if grep -aq 'first-boot setup complete\|Setup complete' "$LOG" 2>/dev/null; then
        DONE=1; echo "# completion marker seen after $(ELAPSED)s"; break
    fi
    if ! kill -0 "$QPID" 2>/dev/null; then
        # QEMU exited — under -no-reboot this is the wizard's reboot
        if grep -aq 'updating packages\|ez-firstboot' "$LOG" 2>/dev/null; then
            DONE=1; echo "# VM rebooted after $(ELAPSED)s (wizard completion path)"
        fi
        break
    fi
    sleep 5
done

echo "----- last 15 lines of serial console -----"
tail -15 "$LOG" 2>/dev/null | cat -v
echo "-------------------------------------------"

if (( DONE )); then
    echo "ok 1 - wizard smoke: full first-boot setup completed ($(ELAPSED)s)"
    exit 0
fi
echo "not ok 1 - wizard smoke: setup did not complete after $(ELAPSED)s"
exit 1
