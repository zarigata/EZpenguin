#!/usr/bin/env bash
# qualify-release.sh — run the COMPLETE release qualification suite.
# Tiers: unit (rootfs chroot) → faults (installer fault injection) →
#        container matrix (all distro rows) → catalog (61 entries) →
#        cli (ez-* commands) → vm (real boot test).
# Usage:
#   tests/matrix/qualify-release.sh            full suite
#   tests/matrix/qualify-release.sh unit|faults|container|catalog|cli|vm
# Evidence: artifacts/qualification/ + artifacts/qualification/RELEASE-REPORT.md
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
Q="$ROOT/artifacts/qualification"
TIER="${1:-all}"
mkdir -p "$Q"
OVERALL=0

run_tier() { # run_tier <name> <logfile> <cmd...>
    local name="$1" logf="$2"; shift 2
    echo "==== tier: $name ===="
    # vm tier must prove a FRESH conversion: drop any disk left by a prior
    # run (a leftover converted disk makes the boot show the EZpenguin
    # banner while SSH auth silently fails on the old authorized_keys)
    if [[ "$name" == vm ]]; then
        rm -rf "$(dirname "$logf")/vm/debian12-inplace" \
               "$(dirname "$logf")/vm/debian-12-generic-amd64.qcow2" \
               "$(dirname "$logf")/vm/image-verified-deb12" 2>/dev/null || true
    fi
    if "$@" >"$logf" 2>&1; then
        echo "  -> $name OK (log: $logf)"
    else
        echo "  -> $name FAILED (log: $logf)"; OVERALL=1
    fi
}

case "$TIER" in
    unit|all)
        # unit tests run against the extracted candidate rootfs in a container
        docker rm -f ezpq-unit >/dev/null 2>&1 || true
        TB=$(find "$ROOT/artifacts" -maxdepth 1 -name 'ezpenguin-*-amd64-rootfs.tar.xz' | sort -r | head -1)
        if [[ -n "$TB" ]]; then
            docker run -d --name ezpq-unit -v "$ROOT:/repo:ro" -v "$TB:/ezp/rootfs.tar.xz:ro" \
                debian:bookworm sleep infinity >/dev/null 2>&1
            docker exec ezpq-unit bash -c 'apt-get update -qq && apt-get install -y -qq xz-utils >/dev/null && mkdir -p /out && cd /out && tar -xJf /ezp/rootfs.tar.xz && bash /repo/tests/run-tests.sh /out amd64' \
                > "$Q/unit.tap" 2>&1 && echo "  -> unit OK" || { echo "  -> unit FAILED"; OVERALL=1; }
            docker rm -f ezpq-unit >/dev/null 2>&1 || true
        else
            echo "  -> unit BLOCKED (no amd64 rootfs tarball)"; OVERALL=1
        fi
        [[ "$TIER" == unit ]] && exit $OVERALL
        ;;
esac
case "$TIER" in
    faults|all) run_tier faults "$Q/faults.log" tests/matrix/test-installer-faults.sh; [[ "$TIER" == faults ]] && exit $OVERALL ;;
esac
case "$TIER" in
    container|all) run_tier container "$Q/container-matrix.log" tests/matrix/qualify-container-matrix.sh; [[ "$TIER" == container ]] && exit $OVERALL ;;
esac
case "$TIER" in
    catalog|all) run_tier catalog "$Q/catalog.log" tests/matrix/qualify-catalog.sh; [[ "$TIER" == catalog ]] && exit $OVERALL ;;
esac
case "$TIER" in
    cli|all) run_tier cli "$Q/cli.log" tests/matrix/qualify-cli.sh; [[ "$TIER" == cli ]] && exit $OVERALL ;;
esac
case "$TIER" in
    vm|all) run_tier vm "$Q/vm.log" tests/matrix/vm-lab.sh debian12-inplace-amd64; [[ "$TIER" == vm ]] && exit $OVERALL ;;
esac

echo
echo "qualification tiers complete — overall: $OVERALL (0=all green)"
exit $OVERALL
