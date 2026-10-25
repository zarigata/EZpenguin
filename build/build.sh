#!/usr/bin/env bash
# build.sh — EZpenguin build pipeline orchestrator.
# Stages: rootfs [arch] | test | image | all
# Runs on host; heavy lifting happens inside Docker.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
# shellcheck source=../config/ezpenguin.cfg
source "$ROOT/config/ezpenguin.cfg"

IMAGE_NAME="ezpenguin-builder:latest"
STAGE="${1:-all}"
ARCH_DEFAULT="amd64"
OUT_VOLUME="ezpenguin-out"

log() { printf '\033[1;32m[ezpenguin]\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31m[ezpenguin] FAIL:\033[0m %s\n' "$*" >&2; exit 1; }

docker_checked() {
    docker info >/dev/null 2>&1 || fail "Docker not running"
}

build_builder() {
    log "building builder image ($IMAGE_NAME)"
    docker build -q -t "$IMAGE_NAME" "$ROOT/build" >/dev/null
}

do_rootfs() {
    local arch="${1:-$ARCH_DEFAULT}"
    docker_checked
    build_builder
    docker volume create "$OUT_VOLUME" >/dev/null
    log "stage: rootfs ($arch)"
    docker run --rm \
        --privileged \
        -v "$ROOT:/build" \
        -v "$OUT_VOLUME:/out" \
        "$IMAGE_NAME" \
        bash /build/build/rootfs.sh "$arch" /build
    docker run --rm -v "$OUT_VOLUME:/out" "$IMAGE_NAME" \
        test -d "/out/rootfs-$arch" || fail "rootfs-$arch not produced"
    log "rootfs-$arch OK"
}

do_test() {
    docker_checked
    build_builder
    local arch="${1:-$ARCH_DEFAULT}"
    log "stage: test ($arch)"
    docker run --rm \
        --privileged \
        -v "$ROOT:/build" \
        -v "$OUT_VOLUME:/out" \
        "$IMAGE_NAME" \
        bash /build/tests/run-tests.sh "/out/rootfs-$arch" "$arch"
    log "tests OK"
}

do_image() {
    docker_checked
    build_builder
    local arch="${1:-$ARCH_DEFAULT}"
    log "stage: image ($arch)"
    mkdir -p "$ROOT/$EZP_ARTIFACT_DIR"
    docker run --rm \
        --privileged \
        -v "$ROOT:/build" \
        -v "$OUT_VOLUME:/out" \
        "$IMAGE_NAME" \
        bash /build/build/image.sh "$arch" /build
    log "artifacts in $EZP_ARTIFACT_DIR/"
}

do_boottest() {
    docker_checked
    build_builder
    local arch="${1:-$ARCH_DEFAULT}"
    local imgx_host="$ROOT/$EZP_ARTIFACT_DIR/ezpenguin-$EZP_VERSION-$arch.img.xz"
    [[ -s "$imgx_host" ]] || fail "no image at $imgx_host — run './build/build.sh image' first"
    log "stage: boottest ($arch) — QEMU full-boot validation"
    docker run --rm \
        --privileged \
        -v "$ROOT:/build" \
        -v "$OUT_VOLUME:/out" \
        "$IMAGE_NAME" \
        bash -c "
            xz -d -c '/build/$EZP_ARTIFACT_DIR/ezpenguin-$EZP_VERSION-$arch.img.xz' > /out/boot-bios.img
            if [ '$arch' = amd64 ]; then
                bash /build/tests/test_boot_vm_retry.sh /out/boot-bios.img 720 bios amd64
            fi
            xz -d -c '/build/$EZP_ARTIFACT_DIR/ezpenguin-$EZP_VERSION-$arch.img.xz' > /out/boot-uefi.img
            bash /build/tests/test_boot_vm_retry.sh /out/boot-uefi.img 720 uefi '$arch'
        "
    log "boot tests OK ($arch)"
}

do_iso() {
    docker_checked
    build_builder
    local arch="${1:-$ARCH_DEFAULT}"
    log "stage: iso ($arch)"
    mkdir -p "$ROOT/$EZP_ARTIFACT_DIR"
    docker run --rm \
        --privileged \
        -v "$ROOT:/build" \
        -v "$OUT_VOLUME:/out" \
        "$IMAGE_NAME" \
        bash /build/build/iso.sh "$arch" /build
    log "ISO in $EZP_ARTIFACT_DIR/"
}

do_isotest() {
    docker_checked
    build_builder
    local arch="${1:-$ARCH_DEFAULT}"
    local iso_host="$ROOT/$EZP_ARTIFACT_DIR/ezpenguin-$EZP_VERSION-$arch.iso"
    [[ -s "$iso_host" ]] || fail "no ISO at $iso_host — run './build/build.sh iso' first"
    log "stage: isotest ($arch) — live ISO boots (BIOS + UEFI)"
    docker run --rm \
        --privileged \
        -v "$ROOT:/build" \
        -v "$OUT_VOLUME:/out" \
        "$IMAGE_NAME" \
        bash -c "
            bash /build/tests/test_iso_boot.sh '/build/$EZP_ARTIFACT_DIR/ezpenguin-$EZP_VERSION-$arch.iso' 900 bios
            bash /build/tests/test_iso_boot.sh '/build/$EZP_ARTIFACT_DIR/ezpenguin-$EZP_VERSION-$arch.iso' 900 uefi
        "
    log "ISO boot tests OK"
}

do_smoke() {
    docker_checked
    build_builder
    local arch="${1:-$ARCH_DEFAULT}"
    log "stage: smoke ($arch) — interactive first-boot wizard walkthrough"
    docker run --rm \
        --privileged \
        -v "$ROOT:/build" \
        -v "$OUT_VOLUME:/out" \
        "$IMAGE_NAME" \
        bash -c "
            xz -d -c '/build/$EZP_ARTIFACT_DIR/ezpenguin-$EZP_VERSION-$arch.img.xz' > /out/smoke.img
            bash /build/tests/test_wizard_smoke.sh /out/smoke.img 1800
        "
    log "wizard smoke test OK"
}

case "$STAGE" in
    rootfs)   do_rootfs   "${2:-$ARCH_DEFAULT}" ;;
    test)     do_test     "${2:-$ARCH_DEFAULT}" ;;
    image)    do_image    "${2:-$ARCH_DEFAULT}" ;;
    boottest) do_boottest "${2:-$ARCH_DEFAULT}" ;;
    iso)      do_iso      "${2:-$ARCH_DEFAULT}" ;;
    isotest)  do_isotest  "${2:-$ARCH_DEFAULT}" ;;
    smoke)    do_smoke    "${2:-$ARCH_DEFAULT}" ;;
    arm64)
        do_rootfs arm64
        do_test   arm64
        do_image  arm64
        do_boottest arm64
        log "arm64 pipeline complete"
        ;;
    all)
        do_rootfs amd64
        do_test   amd64
        do_image  amd64
        do_boottest amd64
        do_iso    amd64
        do_isotest amd64
        do_smoke  amd64
        log "pipeline complete"
        ;;
    *) fail "unknown stage: $STAGE (use: rootfs|test|image|boottest|iso|isotest|smoke|arm64|all)" ;;
esac
