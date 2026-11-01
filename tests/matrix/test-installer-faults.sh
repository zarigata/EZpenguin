#!/usr/bin/env bash
# test-installer-faults.sh — fault-injection tests for the online installer.
# Serves a controlled HTTP fixture (python http.server in a container) and
# points the candidate installer at malformed/corrupt/hostile artifacts.
# Every case asserts the installer REFUSES (non-zero rc, no conversion).
#
# Usage: tests/matrix/test-installer-faults.sh [case-filter]
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/artifacts/qualification/faults"
FILTER="${1:-}"
NET="ezpq-faultnet"
FIX="ezpq-fixture"
SRV="ezpq-http"
BASE_IMG="debian:bookworm-slim"
PASS=0; FAIL=0

mkdir -p "$OUT"
docker network create "$NET" >/dev/null 2>&1 || true
docker rm -f "$SRV" >/dev/null 2>&1 || true

# ---------------------------------------------------------- fixture prep ----
FIXDIR=$(mktemp -d)
trap 'rm -rf "$FIXDIR"; docker rm -f "$SRV" >/dev/null 2>&1' EXIT

# build a minimal-but-valid fake rootfs tarball (id + os-release + a tool)
make_tarball() { # make_tarball <outfile> <corrupt:0|1>
    local out="$1" corrupt="$2"
    local t; t=$(mktemp -d)
    mkdir -p "$t/usr/local/bin" "$t/etc"
    printf 'PRETTY_NAME="EZpenguin TEST"\nID=ezpenguin\nVERSION_ID=0.0.0-test\n' > "$t/etc/os-release"
    printf '#!/bin/sh\necho fake\n' > "$t/usr/local/bin/ez-firstboot"
    chmod +x "$t/usr/local/bin/ez-firstboot"
    printf 'test-rootfs\n' > "$t/usr/local/bin/marker-file"
    tar -C "$t" -cJf "$out" .
    rm -rf "$t"
    if (( corrupt )); then
        # flip bytes in the middle — valid xz container, wrong content
        local size; size=$(stat -f%z "$out" 2>/dev/null || stat -c%s "$out")
        printf 'X' | dd of="$out" bs=1 seek=$((size/2)) conv=notrunc 2>/dev/null
    fi
}

GOOD_TGZ="$FIXDIR/ezpenguin-0.0.0-test-amd64-rootfs.tar.xz"
BAD_TGZ="$FIXDIR/ezpenguin-0.0.0-bad-amd64-rootfs.tar.xz"
make_tarball "$GOOD_TGZ" 0
make_tarball "$BAD_TGZ" 1
GOOD_SUM=$(shasum -a 256 "$GOOD_TGZ" | awk '{print $1}')
BAD_SUM=$(shasum -a 256 "$BAD_TGZ" | awk '{print $1}')

# SHA256SUMS listing the GOOD tarball only (canonical manifest)
printf '%s  ezpenguin-0.0.0-test-amd64-rootfs.tar.xz\n' "$GOOD_SUM" > "$FIXDIR/SHA256SUMS"
# a manifest that lies about the corrupted tarball
printf '%s  ezpenguin-0.0.0-bad-amd64-rootfs.tar.xz\n' "$GOOD_SUM" > "$FIXDIR/SHA256SUMS.lie"
# malformed release JSON
printf '{"message": "API rate limit exceeded"}' > "$FIXDIR/ratelimit.json"
printf '{"not_json_at_all' > "$FIXDIR/garbage.json"
printf '{"tag_name": "v0.0.0-test", "assets": []}' > "$FIXDIR/noassets.json"

docker run -d --name "$SRV" --network "$NET" -v "$FIXDIR:/srv:ro" -w /srv \
    python:3.12-alpine python3 -m http.server 8080 >/dev/null 2>&1 \
    || { echo "FATAL: fixture server failed to start"; exit 1; }
docker exec "$SRV" wget -qO- http://localhost:8080/ >/dev/null 2>&1 || sleep 3
HTTP="http://$SRV:8080"

t() { # t <case-id> <expected: refuse|convert> -- installer-env... ; runs and scores
    local id="$1" expect="$2"; shift 2
    [[ -n "$FILTER" && ! "$id" =~ $FILTER ]] && return 0
    local d="$OUT/$id"; mkdir -p "$d"
    local cname="ezpq-f-$id"

    docker rm -f "$cname" >/dev/null 2>&1
    docker run -d --name "$cname" --network "$NET" --platform linux/amd64 \
        -v "$ROOT/installer:/ezp-installer:ro" "$BASE_IMG" sleep infinity >/dev/null 2>&1
    for _ in $(seq 1 15); do docker exec "$cname" true >/dev/null 2>&1 && break; sleep 1; done
    docker exec "$cname" bash -c 'apt-get update -qq && apt-get install -y -qq curl xz-utils ca-certificates >/dev/null' >/dev/null 2>&1

    # run installer with the case env; record rc + post-state
    docker exec "$cname" env "$@" bash /ezp-installer/online-installer.sh >"$d/install.log" 2>&1
    local rc=$?
    echo "$rc" > "$d/install-rc"
    local state
    state=$(docker exec "$cname" bash -c 'grep -o "^ID=.*" /etc/os-release 2>/dev/null || echo ID=unknown') 
    echo "$state" > "$d/final-state"
    docker rm -f "$cname" >/dev/null 2>&1

    local verdict
    if [[ "$expect" == "refuse" ]]; then
        if (( rc != 0 )) && [[ "$state" != "ID=ezpenguin" ]]; then verdict=PASS; else verdict=FAIL; fi
    else
        if [[ "$state" == "ID=ezpenguin" ]]; then verdict=PASS; else verdict=FAIL; fi
    fi
    echo "$verdict" > "$d/result"
    if [[ "$verdict" == PASS ]]; then PASS=$((PASS+1)); echo "ok   $id (rc=$rc, state=$state)"
    else FAIL=$((FAIL+1)); echo "FAIL $id (rc=$rc, state=$state — wanted $expect)"; tail -3 "$d/install.log" | sed 's/^/      /'; fi
}

echo "# installer fault-injection suite (fixture: $HTTP)"

# ---- happy path through the HTTP fixture (exercises release-lookup code) ----
# valid release JSON pointing at the fixture tarball + real SHA256SUMS
cat > "$FIXDIR/release.json" <<EOF
{"tag_name": "v0.0.0-test", "assets": [
  {"name": "ezpenguin-0.0.0-test-amd64-rootfs.tar.xz", "browser_download_url": "$HTTP/ezpenguin-0.0.0-test-amd64-rootfs.tar.xz"},
  {"name": "SHA256SUMS", "browser_download_url": "$HTTP/SHA256SUMS"}
]}
EOF

t F01-happy-path         convert EZP_MODE=inplace EZP_ASSUME_YES=1 EZP_NO_REBOOT=1 \
    EZP_ARCH=amd64 EZP_API_URL="$HTTP/release.json" EZP_DOWNLOAD_URL="$HTTP"

# ---- corrupted artifact must be rejected -----------------------------------
cat > "$FIXDIR/release-bad.json" <<EOF
{"tag_name": "v0.0.0-bad", "assets": [
  {"name": "ezpenguin-0.0.0-bad-amd64-rootfs.tar.xz", "browser_download_url": "$HTTP/ezpenguin-0.0.0-bad-amd64-rootfs.tar.xz"},
  {"name": "SHA256SUMS", "browser_download_url": "$HTTP/SHA256SUMS.lie"}
]}
EOF
t F02-corrupt-tarball    refuse  EZP_MODE=inplace EZP_ASSUME_YES=1 EZP_NO_REBOOT=1 \
    EZP_ARCH=amd64 EZP_API_URL="$HTTP/release-bad.json" EZP_DOWNLOAD_URL="$HTTP"

# ---- checksum manifest missing entirely + EZP_STRICT must refuse ------------
cat > "$FIXDIR/release-nosums.json" <<EOF
{"tag_name": "v0.0.0-test", "assets": [
  {"name": "ezpenguin-0.0.0-test-amd64-rootfs.tar.xz", "browser_download_url": "$HTTP/ezpenguin-0.0.0-test-amd64-rootfs.tar.xz"}
]}
EOF
t F03-strict-no-sums     refuse  EZP_MODE=inplace EZP_ASSUME_YES=1 EZP_NO_REBOOT=1 \
    EZP_ARCH=amd64 EZP_API_URL="$HTTP/release-nosums.json" EZP_DOWNLOAD_URL="$HTTP" EZP_STRICT=1

# ---- malformed release metadata ---------------------------------------------
t F04-api-garbage        refuse  EZP_MODE=inplace EZP_ASSUME_YES=1 EZP_NO_REBOOT=1 \
    EZP_ARCH=amd64 EZP_API_URL="$HTTP/garbage.json" EZP_DOWNLOAD_URL="$HTTP"
t F05-api-ratelimit      refuse  EZP_MODE=inplace EZP_ASSUME_YES=1 EZP_NO_REBOOT=1 \
    EZP_ARCH=amd64 EZP_API_URL="$HTTP/ratelimit.json" EZP_DOWNLOAD_URL="$HTTP"
t F06-api-no-assets      refuse  EZP_MODE=inplace EZP_ASSUME_YES=1 EZP_NO_REBOOT=1 \
    EZP_ARCH=amd64 EZP_API_URL="$HTTP/noassets.json" EZP_DOWNLOAD_URL="$HTTP"

# ---- asset 404 ----------------------------------------------------------------
cat > "$FIXDIR/release-404.json" <<EOF
{"tag_name": "v0.0.0-test", "assets": [
  {"name": "ezpenguin-0.0.0-test-amd64-rootfs.tar.xz", "browser_download_url": "$HTTP/does-not-exist.tar.xz"},
  {"name": "SHA256SUMS", "browser_download_url": "$HTTP/SHA256SUMS"}
]}
EOF
t F07-asset-404          refuse  EZP_MODE=inplace EZP_ASSUME_YES=1 EZP_NO_REBOOT=1 \
    EZP_ARCH=amd64 EZP_API_URL="$HTTP/release-404.json"

# ---- DNS failure ----------------------------------------------------------------
t F08-dns-failure        refuse  EZP_MODE=inplace EZP_ASSUME_YES=1 EZP_NO_REBOOT=1 \
    EZP_ARCH=amd64 EZP_API_URL="https://nonexistent.invalid/never.json" EZP_DOWNLOAD_URL="$HTTP"

# ---- hostile archive: path traversal + symlink attack ---------------------------
TRAV="$FIXDIR/traversal.json"
# build an evil tarball outside FIXDIR serving dir? No — build in FIXDIR and
# check the installer refuses. tar itself strips leading / and refuses .. in
# member names by default (GNU tar), so conversion must not pwn /target.
EVIL=$(mktemp -d)
mkdir -p "$EVIL/pwned"
printf 'OWNED\n' > "$EVIL/pwned/canary"
( cd "$EVIL" && tar -cJf "$FIXDIR/evil.tar.xz" --transform 's|^pwned|../../../tmp/pwned-evil|' pwned 2>/dev/null || tar -cJf "$FIXDIR/evil.tar.xz" pwned )
EVIL_SUM=$(shasum -a 256 "$FIXDIR/evil.tar.xz" | awk '{print $1}')
printf '%s  evil.tar.xz\n' "$EVIL_SUM" > "$FIXDIR/SHA256SUMS.evil"
cat > "$TRAV" <<EOF
{"tag_name": "v0.0.0-evil", "assets": [
  {"name": "evil.tar.xz", "browser_download_url": "$HTTP/evil.tar.xz"},
  {"name": "SHA256SUMS", "browser_download_url": "$HTTP/SHA256SUMS.evil"}
]}
EOF
t F09-malicious-paths    refuse  EZP_MODE=inplace EZP_ASSUME_YES=1 EZP_NO_REBOOT=1 \
    EZP_ARCH=amd64 EZP_API_URL="$TRAV" EZP_DOWNLOAD_URL="$HTTP"

# ---- unsupported family refusal (fedora) ----------------------------------------
docker rm -f ezpq-f-fedora >/dev/null 2>&1
if docker pull -q fedora:41 >/dev/null 2>&1; then
    d="$OUT/F10-fedora-refused"; mkdir -p "$d"
    docker run -d --name ezpq-f-fedora --network "$NET" fedora:41 sleep infinity >/dev/null 2>&1
    docker exec ezpq-f-fedora dnf install -y -q curl xz >/dev/null 2>&1
    docker exec -e EZP_TARBALL="$HTTP/ezpenguin-0.0.0-test-amd64-rootfs.tar.xz" \
        -e EZP_MODE=inplace -e EZP_ASSUME_YES=1 -e EZP_NO_REBOOT=1 \
        ezpq-f-fedora bash /ezp-installer/online-installer.sh >"$d/install.log" 2>&1
    rc=$?
    state=$(docker exec ezpq-f-fedora grep -o '^ID=.*' /etc/os-release | head -1)
    if (( rc != 0 )) && [[ "$state" == "ID=fedora" ]]; then
        echo PASS > "$d/result"; PASS=$((PASS+1)); echo "ok   F10-fedora-refused (rc=$rc, $state intact)"
    else
        echo FAIL > "$d/result"; FAIL=$((FAIL+1)); echo "FAIL F10-fedora-refused (rc=$rc, state=$state)"
    fi
    docker rm -f ezpq-f-fedora >/dev/null 2>&1
else
    mkdir -p "$OUT/F10-fedora-refused"; echo BLOCKED > "$OUT/F10-fedora-refused/result"
    BLOCKED=1
    echo "BLKD F10-fedora-refused (pull failed)"
fi

# ---- arch mismatch: arm64 installer on amd64 host must refuse --------------------
t F11-arch-mismatch      refuse  EZP_MODE=inplace EZP_ASSUME_YES=1 EZP_NO_REBOOT=1 \
    EZP_ARCH=riscv64 EZP_TARBALL="$HTTP/ezpenguin-0.0.0-test-amd64-rootfs.tar.xz"

echo
echo "# fault suite: pass=$PASS fail=$FAIL blocked=${BLOCKED:-0}"
(( FAIL == 0 )) || exit 1
