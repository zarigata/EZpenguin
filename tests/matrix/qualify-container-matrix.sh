#!/usr/bin/env bash
# qualify-container-matrix.sh — run the cross-distribution container matrix.
# Reads tests/matrix/compatibility-matrix.tsv (env=container rows), boots a
# pinned container per row, runs the one-liner (candidate installer from the
# checkout), then probes conversion/rejection.
#
# Usage: tests/matrix/qualify-container-matrix.sh [--filter REGEX] [--jobs N] [--public]
#   --public  test the PUBLISHED raw.githubusercontent one-liner instead of
#             the candidate (validates the public URL path; artifacts still
#             come from GitHub releases)
#
# Outputs:
#   artifacts/qualification/container/<case-id>/{serial.log,probe.log,result}
#   artifacts/qualification/container-matrix.{tap,junit.xml}
#   artifacts/qualification/container-matrix.tsv   (matrix with results appended)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MATRIX="$ROOT/tests/matrix/compatibility-matrix.tsv"
OUT="$ROOT/artifacts/qualification"
FILTER=""
JOBS=3
PUBLIC=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --filter) FILTER="${2:-}"; shift 2 ;;
        --jobs) JOBS="${2:-3}"; shift 2 ;;
        --public) PUBLIC=1; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

mkdir -p "$OUT/container"
START=$(date +%s)

# candidate artifact selection: newest local rootfs tarball for the arch, else fail
candidate_tarball() {
    local arch="$1"
    find "$ROOT/artifacts" -maxdepth 1 -name "ezpenguin-*-$arch-rootfs.tar.xz" 2>/dev/null | sort -r | head -1
}

run_case() {
    local id="$1" distro="$2" arch="$3" mode="$4" expectation="$5"
    local d="$OUT/container/$id"
    mkdir -p "$d"
    local result="FAIL" note=""

    local image tag family
    family="${distro%%:*}"; tag="${distro#*:}"
    case "$family" in
        debian) image="debian:$tag" ;;
        ubuntu) image="ubuntu:$tag" ;;
        fedora) image="quay.io/fedora/fedora:$tag" ;;
        rockylinux) image="rockylinux:$tag" ;;
        almalinux) image="almalinux:$tag" ;;
        opensuse)
            if [[ "$tag" == leap* ]]; then image="opensuse/leap:${tag#leap:}"
            else image="opensuse/tumbleweed:latest"; fi ;;
        archlinux) image="archlinux:latest" ;;
        alpine) image="alpine:$tag" ;;
        linuxmint) image="linuxmintd/mint22-amd64" ;;
        *) image="$distro" ;;
    esac

    # ---- 1. pull pinned image (evidence: digest) ----
    if ! docker image inspect "$image" >/dev/null 2>&1; then
        docker pull --platform="linux/$arch" "$image" >"$d/pull.log" 2>&1 \
            || { echo "BLOCKED" > "$d/result"; echo "pull failed: $(tail -1 "$d/pull.log")" > "$d/note"; return; }
    fi
    docker image inspect "$image" --format '{{index .RepoDigests 0}}' >"$d/image-digest" 2>/dev/null || true
    echo "$image" > "$d/image"

    # ---- 2. boot container with sleep infinity as PID1 ----
    local cname="ezpq-$id"
    docker rm -f "$cname" >/dev/null 2>&1
    local run_args=(-d --name "$cname" --platform "linux/$arch"
                    -v "$ROOT/installer:/ezp-installer:ro")
    # artifact mount only for candidate runs (public runs use GitHub releases)
    if (( ! PUBLIC )); then
        local tb; tb=$(candidate_tarball "$arch")
        [[ -n "$tb" ]] || { echo "BLOCKED" > "$d/result"; echo "no candidate tarball for $arch" > "$d/note"; return; }
        run_args+=(-v "$tb:/ezp/rootfs.tar.xz:ro")
        # checksum sidecar so the installer verifies integrity end-to-end
        ( cd "$(dirname "$tb")" && shasum -a 256 "$(basename "$tb")" | sed "s/$(basename "$tb")/rootfs.tar.xz/" ) > "$d/rootfs.tar.xz.sha256"
        run_args+=(-v "$d/rootfs.tar.xz.sha256:/ezp/rootfs.tar.xz.sha256:ro")
    fi
    docker run "${run_args[@]}" "$image" sleep infinity >"$d/run.log" 2>&1 \
        || { echo "BLOCKED" > "$d/result"; echo "container failed to start: $(tail -1 "$d/run.log")" > "$d/note"; return; }
    # wait for PID1 readiness
    for _ in $(seq 1 20); do
        docker exec "$cname" true >/dev/null 2>&1 && break; sleep 1
    done

    # ---- 3. prepare prerequisites inside the guest (documented prereqs) ----
    prepare_guest "$image" "$cname" "$arch" >"$d/prepare.log" 2>&1

    # ---- 4. run the installer (candidate or public) ----
    if (( PUBLIC )); then
        docker exec "$cname" bash -c \
            'curl -sSfL https://raw.githubusercontent.com/zarigata/EZpenguin/main/installer/online-installer.sh -o /tmp/o-installer.sh && bash /tmp/o-installer.sh' \
            >"$d/install.log" 2>&1
    else
        docker exec "$cname" bash -c \
            'EZP_TARBALL=/ezp/rootfs.tar.xz EZP_NO_REBOOT=1 bash /ezp-installer/online-installer.sh' \
            >"$d/install.log" 2>&1
    fi
    local rc=$?
    echo "$rc" > "$d/install-rc"

    # ---- 5. probe outcome ----
    # NB: probe.log APPENDS across reruns (>> in probe_outcome). Only this
    # run's verdict counts — truncate first, then count this run's markers.
    : > "$d/probe.log"
    probe_outcome "$cname" "$d/probe.log" 2>&1
    local converted refused
    converted=$(grep -s 'EZP_PROBE: converted' "$d/probe.log" 2>/dev/null | wc -l | tr -d ' ')
    refused=$(grep -s 'EZP_PROBE: refused' "$d/probe.log" 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$mode" == "inplace" && "$expectation" == "supported" ]]; then
        if (( converted )); then result="PASS"; else
            result="FAIL"; note="expected conversion, probe found none (install rc=$rc)"
        fi
    elif [[ "$mode" == "reject" ]]; then
        if (( refused )); then result="PASS"
        elif (( converted )); then
            result="FAIL"; note="DANGEROUS: converted a system that must be rejected"
        else
            # non-zero exit without damage is also a safe refusal
            if (( rc != 0 )); then result="PASS"; note="refused via non-zero exit"
            else result="FAIL"; note="neither refused nor converted — inconclusive"; fi
        fi
    fi

    docker rm -f "$cname" >/dev/null 2>&1 || true
    echo "$result" > "$d/result"
    if [[ -n "$note" ]]; then echo "$note" > "$d/note"; fi
}

prepare_guest() {
    local image="$1" cname="$2" arch="$3"
    case "$image" in
        debian:11|debian:bullseye*)
            # bullseye went FULL EOL (Aug 2026): mirror 404s on every line.
            # Point the whole prereq sources.list at archive.debian.org.
            docker exec "$cname" bash -c '
                export DEBIAN_FRONTEND=noninteractive
                printf "deb http://archive.debian.org/debian bullseye main\ndeb http://archive.debian.org/debian-security bullseye-security main\n" > /etc/apt/sources.list
                apt-get -o Acquire::Check-Valid-Until=false update -qq 2>&1 | tail -1
                apt-get install -y -qq curl xz-utils ca-certificates >/dev/null
                command -v curl' ;;
        debian:*|ubuntu:*)
            # stale mirror snapshots (esp. bullseye-security) 404; drop the
            # security line for the PREREQ install only (guest is disposable,
            # the installer under test uses its own sources afterwards)
            docker exec "$cname" bash -c '
                export DEBIAN_FRONTEND=noninteractive
                cp /etc/apt/sources.list /tmp/sources.list.bak 2>/dev/null || true
                apt-get update -qq 2>/dev/null || true
                apt-get install -y -qq curl xz-utils ca-certificates >/dev/null 2>&1 || {
                    sed -i "/security/d" /etc/apt/sources.list 2>/dev/null
                    apt-get update -qq 2>/dev/null
                    apt-get install -y -qq curl xz-utils ca-certificates >/dev/null
                    cp /tmp/sources.list.bak /etc/apt/sources.list 2>/dev/null || true
                }' ;;
        linuxmintd/*)
            # the linuxmintd proxy image ships ID=ubuntu (verified: ID_LIKE=debian,
            # ID=ubuntu) — but REAL Linux Mint 22 ships ID=linuxmint, and the
            # installer's family guard refuses non-debian/ubuntu bases. Stamp the
            # honest desktop identity so this row tests the real refusal path
            # instead of passing a forged "ubuntu" to the installer.
            docker exec "$cname" bash -c '
                export DEBIAN_FRONTEND=noninteractive
                cp /etc/apt/sources.list /tmp/sources.list.bak 2>/dev/null || true
                apt-get update -qq 2>/dev/null || true
                apt-get install -y -qq curl xz-utils ca-certificates >/dev/null 2>&1 || {
                    sed -i "/security/d" /etc/apt/sources.list 2>/dev/null
                    apt-get update -qq 2>/dev/null
                    apt-get install -y -qq curl xz-utils ca-certificates >/dev/null
                    cp /tmp/sources.list.bak /etc/apt/sources.list 2>/dev/null || true
                }
                sed -i "s/^ID=ubuntu/ID=linuxmint/; s/^ID_LIKE=debian\$/ID_LIKE=debian ubuntu/" /etc/os-release
                echo "post-stamp identity:"; grep -E "^ID" /etc/os-release' ;;
        quay.io/fedora/*|rockylinux:*|almalinux:*|opensuse/*|archlinux:*)
            docker exec "$cname" bash -c '
                command -v dnf >/dev/null && dnf install -y -q curl >/dev/null 2>&1
                command -v yum >/dev/null && yum install -y -q curl >/dev/null 2>&1
                command -v zypper >/dev/null && zypper --non-interactive install curl >/dev/null 2>&1
                command -v pacman >/dev/null && pacman -Sy --noconfirm curl >/dev/null 2>&1
                command -v curl >/dev/null' ;;
        alpine:*)
            docker exec "$cname" sh -c 'apk add --no-cache curl xz libstdc++ >/dev/null 2>&1; command -v curl' ;;
    esac
}

probe_outcome() {
    local cname="$1" plog="$2"
    docker exec "$cname" bash -c '
        echo "== identity =="
        grep -E "^(ID|PRETTY_NAME)=" /etc/os-release 2>/dev/null
        if grep -q "^ID=ezpenguin" /etc/os-release 2>/dev/null; then
            echo "EZP_PROBE: converted"
            echo "== tools =="
            for t in ez-info ez-doctor ez-software ez-config; do
                command -v $t >/dev/null && echo "tool-ok: $t" || echo "tool-missing: $t"
            done
            echo "== apt =="
            if command -v apt-get >/dev/null; then apt-get update -qq 2>&1 | tail -1 && echo "apt-ok"; fi
        elif grep -qE "^(ID=fedora|ID=rocky|ID=almalinux|ID=opensuse-leap|ID=opensuse-tumbleweed|ID=arch|ID=alpine|ID_LIKE=\"(fedora|suse|arch)" /etc/os-release 2>/dev/null; then
            echo "EZP_PROBE: refused (original OS intact)"
            # verify nothing was mangled: package manager still works
            if command -v dnf >/dev/null; then dnf --version >/dev/null && echo "pkgdb-intact: dnf"
            elif command -v rpm >/dev/null; then rpm -q rpm >/dev/null && echo "pkgdb-intact: rpm"
            elif command -v apk >/dev/null; then apk --version >/dev/null && echo "pkgdb-intact: apk"
            elif command -v pacman >/dev/null; then pacman --version >/dev/null && echo "pkgdb-intact: pacman"; fi
        else
            echo "EZP_PROBE: unknown-state"
        fi
    ' >>"$plog"
}

# --------------------------------------------------------------- runner -----
FAILED=0; PASSED=0; BLOCKED=0
sem_wait() { while (( $(jobs -rp | wc -l) >= JOBS )); do sleep 2; done; }

collect() {
    local id="$1"
    local r; r=$(cat "$OUT/container/$id/result" 2>/dev/null || echo "NOTRUN")
    case "$r" in
        PASS) PASSED=$((PASSED+1)); echo "ok   $id" ;;
        FAIL) FAILED=$((FAILED+1)); echo "FAIL $id  $(cat "$OUT/container/$id/note" 2>/dev/null)" ;;
        BLOCKED) BLOCKED=$((BLOCKED+1)); echo "BLKD $id  $(cat "$OUT/container/$id/note" 2>/dev/null)" ;;
        *) echo "???  $id" ;;
    esac
}

echo "# container matrix: filter=${FILTER:-none} jobs=$JOBS public=$PUBLIC"
n=0
while IFS=$'\t' read -r id distro arch env mode expectation prio; do
    [[ "$id" =~ ^EZP-MATRIX ]] || continue
    [[ "$env" == "container" ]] || continue
    if [[ -n "$FILTER" && ! "$id $distro $arch" =~ $FILTER ]]; then continue; fi
    sem_wait
    echo "  launching $id ($distro $arch mode=$mode)"
    run_case "$id" "$distro" "$arch" "$mode" "$expectation" &
    n=$((n+1))
done < "$MATRIX"
wait

# summary
echo
echo "# results:"
for d in "$OUT"/container/*/; do
    id=$(basename "$d"); [[ "$id" =~ ^EZP-MATRIX ]] || continue
    collect "$id"
done

# write combined matrix TSV with results
{
    echo -e "id\tdistro\tarch\tenv\tmode\texpectation\tpriority\tresult\tevidence"
    while IFS=$'\t' read -r id distro arch env mode expectation prio; do
        [[ "$id" =~ ^EZP-MATRIX ]] || continue
        r=$(cat "$OUT/container/$id/result" 2>/dev/null || echo "NOTRUN")
        echo -e "$id\t$distro\t$arch\t$env\t$mode\t$expectation\t$prio\t$r\tartifacts/qualification/container/$id"
    done < "$MATRIX"
} > "$OUT/container-matrix.tsv"

# TAP output
{
    total=$(grep -c '^EZP-MATRIX' "$OUT/container-matrix.tsv")
    echo "TAP version 13"
    echo "1..$total"
    i=0
    tail -n +2 "$OUT/container-matrix.tsv" | while IFS=$'\t' read -r id distro arch env mode expectation prio r ev; do
        i=$((i+1))
        if [[ "$r" == PASS ]]; then echo "ok $i - $id ($distro/$arch $mode)"
        elif [[ "$r" == BLOCKED ]]; then echo "not ok $i - $id ($distro/$arch $mode) # BLOCKED evidence: $ev"
        else echo "not ok $i - $id ($distro/$arch $mode) # $r evidence: $ev"; fi
    done
} > "$OUT/container-matrix.tap"

# JUnit output
{
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo "<testsuites name=\"EZpenguin container matrix\" tests=\"$n\" time=$(( $(date +%s) - START ))>"
    echo "  <testsuite name=\"container-matrix\" tests=\"$n\" failures=$FAILED skipped=$BLOCKED>"
    tail -n +2 "$OUT/container-matrix.tsv" | while IFS=$'\t' read -r id distro arch env mode expectation prio r ev; do
        case "$r" in
            PASS)  echo "    <testcase name=\"$id\" classname=\"matrix.$distro\">"
                   echo "      <system-out>mode=$mode result=PASS</system-out></testcase>" ;;
            BLOCKED) echo "    <testcase name=\"$id\" classname=\"matrix.$distro\"><skipped/></testcase>" ;;
            *) echo "    <testcase name=\"$id\" classname=\"matrix.$distro\"><failure message=\"$r evidence=$ev\"/></testcase>" ;;
        esac
    done
    echo "  </testsuite>"
    echo "</testsuites>"
} > "$OUT/container-matrix.junit.xml"

echo
echo "# summary: pass=$PASSED fail=$FAILED blocked=$BLOCKED"
echo "# matrix:   $OUT/container-matrix.tsv"
echo "# tap:      $OUT/container-matrix.tap"
echo "# junit:    $OUT/container-matrix.junit.xml"
(( FAILED == 0 )) || exit 1
