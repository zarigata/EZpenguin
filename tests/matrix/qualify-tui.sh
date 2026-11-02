#!/usr/bin/env bash
# qualify-tui.sh — drive the ez-soft TUI inside a real pty (util-linux
# `script`) in one container per variant: debian:12, ubuntu:24.04, debian:11.
# Per variant the suite: renders one frame, toggles a selection by keystroke,
# installs `tree` via keystrokes (filter /tree, i, y), quits cleanly, and
# checks `sudo ez-software` delegates to ez-soft on a TTY.
#
# Evidence: artifacts/qualification/tui.{tap,tsv,junit.xml}
#           artifacts/qualification/tui/<variant>/{frame,toggle,install,deleg}.out
# Usage: tests/matrix/qualify-tui.sh [IMAGE...]   (default: debian:12
#        ubuntu:24.04 debian:11; KEEP=1 keeps containers for debugging)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/artifacts/qualification"
CATALOG="$ROOT/rootfs-overlay/etc/ezpenguin/software-catalog.list"
EZSOFT="$ROOT/rootfs-overlay/usr/local/bin/ez-soft"
EZSOFTWARE="$ROOT/rootfs-overlay/usr/local/bin/ez-software"
VARIANTS=()
if (( $# )); then VARIANTS=("$@"); else VARIANTS=(debian:12 ubuntu:24.04 debian:11); fi
KEEP="${KEEP:-0}"

for f in "$CATALOG" "$EZSOFT" "$EZSOFTWARE"; do
    [[ -e "$f" ]] || { echo "FATAL: missing $f" >&2; exit 1; }
done
mkdir -p "$OUT/tui"
START=$(date +%s)
PASS=0 FAIL=0 BLOCKED=0
TAP="$OUT/tui.tap"; TSV="$OUT/tui.tsv"
printf 'TAP version 13\n' > "$TAP"
printf 'variant\tprobe\tresult\tnote\n' > "$TSV"

record() { # record <variant> <probe> <result> [note]
    local v="$1" p="$2" r="$3" note="${4:-}"
    case "$r" in
        PASS)   PASS=$((PASS+1)); echo "ok $((PASS+FAIL+BLOCKED)) - tui/$v/$p" >> "$TAP" ;;
        BLOCKED) BLOCKED=$((BLOCKED+1)); echo "not ok $((PASS+FAIL+BLOCKED)) - tui/$v/$p # BLOCKED: $note" >> "$TAP" ;;
        *)      FAIL=$((FAIL+1)); echo "not ok $((PASS+FAIL+BLOCKED)) - tui/$v/$p # $note" >> "$TAP" ;;
    esac
    printf '%s\t%s\t%s\t%s\n' "$v" "$p" "$r" "$note" >> "$TSV"
}

run_variant() { # run_variant <image>
    local img="$1"
    local cname="ezpq-tui-$(echo "$img" | tr ':/' '--')"
    local vd="$OUT/tui/$cname"
    mkdir -p "$vd"
    docker rm -f "$cname" >/dev/null 2>&1 || true
    echo "== $img (container $cname)"

    docker run -d --name "$cname" \
        -v "$CATALOG:/tmp/ezp-catalog.list:ro" \
        -v "$EZSOFT:/tmp/ezp-ez-soft:ro" \
        -v "$EZSOFTWARE:/tmp/ezp-ez-software:ro" \
        "$img" sleep infinity >"$vd/run.log" 2>&1 \
        || { record "$img" setup BLOCKED "container failed to start: $(tail -1 "$vd/run.log" | cut -c1-80)"; return; }

    # ro binds from macOS lose exec bits — install to real paths
    docker exec "$cname" bash -c '
        mkdir -p /etc/ezpenguin /usr/local/bin
        install -m 0755 /tmp/ezp-ez-soft /usr/local/bin/ez-soft
        install -m 0755 /tmp/ezp-ez-software /usr/local/bin/ez-software
        install -m 0644 /tmp/ezp-catalog.list /etc/ezpenguin/software-catalog.list
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq >/dev/null 2>&1 || true
        apt-get install -y -qq util-linux bsdutils procps >/dev/null 2>&1 || true' >>"$vd/setup.log" 2>&1

    if ! docker exec "$cname" bash -c 'command -v script >/dev/null && command -v stty >/dev/null'; then
        record "$img" setup BLOCKED "util-linux script/stty unavailable in this image"
        (( KEEP )) || docker rm -f "$cname" >/dev/null 2>&1 || true
        return
    fi
    record "$img" setup PASS ""

    # pty driver: feed keystrokes to `script`, capture the whole session;
    # script -e returns the child's exit code.
    tui_run() { # tui_run <outfile-in-guest> <keystrokes>
        docker exec "$cname" bash -c "printf '%s' \"\$2\" | timeout 240 script -qfe -c 'TERM=xterm ez-soft' \"\$1\"" \
            >/dev/null 2>&1
    }

    # -- probe 1: render one frame, quit -------------------------------------
    echo "   probe: render"
    local rc=0
    # util-linux script consumes ALL stdin before starting the child, so
    # keystrokes must be fed gradually (sleeps keep the pipe open) and every
    # feed MUST end in an explicit exit key — script never propagates EOF.
    docker exec "$cname" bash -c "printf q | timeout 120 script -qfe -c 'TERM=xterm ez-soft' /tmp/frame.out" >/dev/null 2>&1 || rc=$?
    if [[ $rc -ne 0 ]]; then
        record "$img" render FAIL "script rc=$rc (see $vd)"
    elif ! docker exec "$cname" test -s /tmp/frame.out; then
        record "$img" render FAIL "frame capture empty"
    else
        if docker exec "$cname" bash -c "grep -q 'EZpenguin software' /tmp/frame.out && grep -q 'entries /' /tmp/frame.out && grep -q '\[ \]' /tmp/frame.out"; then
            record "$img" render PASS ""
            docker exec "$cname" cat /tmp/frame.out > "$vd/frame.out" 2>/dev/null || true
        else
            record "$img" render FAIL "frame missing TUI markers"
        fi
    fi

    # -- probe 2: move + toggle selection, quit -------------------------------
    echo "   probe: toggle"
    # NB: after the toggle one entry is selected, so `q` raises the quit
    # confirm overlay — the feed must answer it with `y`.
    local trc=0
    docker exec "$cname" bash -c '( printf "\033[B"; sleep 1; printf " "; sleep 1; printf "q"; sleep 1; printf "y" ) | timeout 120 script -qfe -c "TERM=xterm ez-soft" /tmp/toggle.out' >/dev/null 2>&1 || trc=$?
    if [[ $trc -ne 0 ]]; then
        record "$img" toggle FAIL "script rc=$trc during keystroke toggle (see $vd)"
    elif docker exec "$cname" bash -c "grep -q '\[x\]' /tmp/toggle.out"; then
        record "$img" toggle PASS ""
        docker exec "$cname" cat /tmp/toggle.out > "$vd/toggle.out" 2>/dev/null || true
    else
        record "$img" toggle FAIL "no [x] marker after space toggle"
    fi

    # -- probe 3: install tree via keystrokes ---------------------------------
    echo "   probe: install (apt, ~30-90s)"
    # keys: / filter, tree<enter>, space toggle, i install, y confirm,
    #       (wait for apt), <enter> dismiss "press enter", q quit
    local irc=0
    docker exec "$cname" bash -c '( printf "/"; sleep 0.5; printf "tree"; sleep 0.5; printf "\r"; sleep 1; printf " "; sleep 0.5; printf "i"; sleep 1; printf "y"; sleep 60; printf "\r"; sleep 1; printf "q" ) | timeout 240 script -qfe -c "TERM=xterm ez-soft" /tmp/install.out' >/dev/null 2>&1 || irc=$?
    local has_tree=0
    docker exec "$cname" bash -c 'command -v tree >/dev/null' || has_tree=$?
    if [[ $irc -ne 0 ]]; then
        record "$img" install FAIL "script rc=$irc during keystroke install"
    elif [[ $has_tree -ne 0 ]]; then
        record "$img" install FAIL "tree binary absent after keystroke install"
    elif ! docker exec "$cname" grep -q 'installed 1 item(s)' /tmp/install.out; then
        record "$img" install FAIL "tree installed but no 'installed 1 item(s)' summary"
    else
        record "$img" install PASS ""
        docker exec "$cname" cat /tmp/install.out > "$vd/install.out" 2>/dev/null || true
    fi

    # -- probe 4: quit confirm with pending selection --------------------------
    echo "   probe: quit-confirm"
    # keys: a select-all, q quit -> confirm overlay, y = yes
    local qrc=0
    docker exec "$cname" bash -c '( printf "a"; sleep 1; printf "q"; sleep 1; printf "y" ) | timeout 120 script -qfe -c "TERM=xterm ez-soft" /tmp/quit.out' >/dev/null 2>&1 || qrc=$?
    if [[ $qrc -eq 0 ]]; then
        record "$img" quit-confirm PASS ""
        docker exec "$cname" cat /tmp/quit.out > "$vd/quit.out" 2>/dev/null || true
    else
        record "$img" quit-confirm FAIL "rc=$qrc — select-all, q, y did not exit cleanly"
    fi

    # -- probe 5: ez-software delegates to ez-soft on a TTY --------------------
    echo "   probe: delegation"
    docker exec "$cname" bash -c "printf q | timeout 120 script -qfe -c 'TERM=xterm ez-software' /tmp/deleg.out" >/dev/null 2>&1
    if docker exec "$cname" bash -c "grep -q 'EZpenguin software' /tmp/deleg.out"; then
        record "$img" delegation PASS ""
        docker exec "$cname" cat /tmp/deleg.out > "$vd/deleg.out" 2>/dev/null || true
    else
        record "$img" delegation FAIL "ez-software on a pty did not render the ez-soft frame"
    fi

    (( KEEP )) || docker rm -f "$cname" >/dev/null 2>&1 || true
}

for v in "${VARIANTS[@]}"; do
    run_variant "$v"
done

# ---- junit -------------------------------------------------------------------
{
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    N=$((PASS+FAIL+BLOCKED))
    echo "<testsuites name=\"EZpenguin ez-soft TUI pty\" tests=\"$N\" time=$(( $(date +%s) - START ))>"
    echo "  <testsuite name=\"tui\" tests=\"$N\" failures=\"$FAIL\" skipped=\"$BLOCKED\">"
    tail -n +2 "$TSV" | while IFS=$'\t' read -r variant probe result note; do
        case "$result" in
            PASS)    echo "    <testcase name=\"tui.$variant.$probe\" classname=\"tui.$variant\"/>" ;;
            BLOCKED) echo "    <testcase name=\"tui.$variant.$probe\" classname=\"tui.$variant\"><skipped message=\"$note\"/></testcase>" ;;
            *)       echo "    <testcase name=\"tui.$variant.$probe\" classname=\"tui.$variant\"><failure message=\"$result: $note\"/></testcase>" ;;
        esac
    done
    echo "  </testsuite>"
    echo "</testsuites>"
} > "$OUT/tui.junit.xml"

echo
echo "# tui results: pass=$PASS fail=$FAIL blocked=$BLOCKED (variants: ${VARIANTS[*]})"
echo "# tap:   $TAP"
echo "# tsv:   $TSV"
echo "# junit: $OUT/tui.junit.xml"
(( FAIL == 0 )) || exit 1
exit 0
