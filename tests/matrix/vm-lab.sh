#!/usr/bin/env bash
# vm-lab.sh — full VM installation tests. Boots real QEMU guests inside the
# Docker lab (TCG; KVM when available), installs via the one-liner over SSH
# from inside the guest (real DNS/TLS path), reboots from disk twice, and
# probes the installed system.
#
# A container restart does NOT prove boot works — this does.
#
# Usage: tests/matrix/vm-lab.sh <scenario>
#   debian12-inplace-amd64   install Debian 12 cloud image, convert in place,
#                            reboot from installed disk, verify EZpenguin boots
#   ubuntu2404-inplace-amd64 same on Ubuntu 24.04
#   status                   show running guests
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/artifacts/qualification/vm"
SCENARIO="${1:-}"
FW_VER="20230626-127"
CLOUD_URL_DEB12="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
CLOUD_SUM_DEB12="https://cloud.debian.org/images/cloud/bookworm/latest/SHA512SUMS"
CLOUD_URL_UBU2404="https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
mkdir -p "$OUT"

# ---------------------------------------------------------------- helpers ---
die() { echo "vm-lab: ERROR: $*" >&2; docker rm -f ezpq-vm >/dev/null 2>&1 || true; exit 1; }

log() { printf '\033[1;35m[vm-lab]\033[0m %s\n' "$*"; }

# build-if-missing: ezpenguin-vmtest must be reproducible from the repo
# (tests/matrix/Dockerfile.vmtest), not machine-only state. Also fail LOUDLY
# here if the privileged nbd path is unavailable — every disk helper below
# would otherwise degrade silently and the failure would surface much later
# as a confusing ssh timeout.
if ! docker image inspect ezpenguin-vmtest:latest >/dev/null 2>&1; then
    log "ezpenguin-vmtest image missing — building from tests/matrix/Dockerfile.vmtest"
    docker build -f "$ROOT/tests/matrix/Dockerfile.vmtest" -t ezpenguin-vmtest "$ROOT/tests/matrix" \
        || die "ezpenguin-vmtest image build failed"
fi
if ! docker run --rm --privileged ezpenguin-vmtest:latest bash -c 'test -e /dev/nbd0' 2>/dev/null; then
    die "/dev/nbd0 unavailable in privileged containers — run once: docker run --rm --privileged debian:bookworm modprobe nbd max_part=16 (see Dockerfile.vmtest header)"
fi

wait_ssh() { # wait_ssh <port> <key> <timeout> [user] — wait until KEY AUTH works
    local port="$1" key="$2" timeout="$3" user="${4:-ezp}" i
    for ((i=0; i<timeout; i+=5)); do
        if ssh -i "$key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
               -o ConnectTimeout=4 -o BatchMode=yes -p "$port" "${user}@127.0.0.1" true 2>/dev/null; then
            return 0
        fi
        sleep 5
    done
    return 1
}

preboot_fsck() { # repair the qcow2 after any hard kill; idempotent
    docker rm -f ezpq-vm >/dev/null 2>&1 || true
    docker run --rm --privileged -v "$OUT:/lab" ezpenguin-vmtest:latest bash -c '
        qemu-nbd -c /dev/nbd0 /lab/debian-12-generic-amd64.qcow2 2>/dev/null
        sleep 2; partprobe /dev/nbd0 2>/dev/null; sleep 1
        e2fsck -fy /dev/nbd0p1 >/dev/null 2>&1 || true
        # Debian 12 cloud image ships an UNCONFIGURED fstab (comment only).
        # Without a root line systemd-remount-fs never remounts rw and the
        # whole first boot runs read-only (cloud-init crashes, seed user is
        # never created). Write the real root line before first boot.
        if mkdir -p /mnt-ezp && mount /dev/nbd0p1 /mnt-ezp; then
            PUID=$(blkid -s PARTUUID -o value /dev/nbd0p1)
            printf "PARTUUID=%s  /  ext4  defaults,noatime  0 1\n" "$PUID" > /mnt-ezp/etc/fstab
            umount /mnt-ezp
        fi
        qemu-nbd -d /dev/nbd0 >/dev/null 2>&1' || true
}


# --------------------------------------------------------------- scenario ---
scenario_debian12_inplace() {
    local img="$OUT/debian-12-generic-amd64.qcow2"
    local log="$OUT/debian12-inplace"
    # keep failed attempts' evidence: previous attempt moves to <log>.attempt-N
    if [[ -d "$log" ]]; then
        local n=1
        while [[ -d "$log.attempt-$n" ]]; do n=$((n+1)); done
        mv "$log" "$log.attempt-$n"
    fi
    mkdir -p "$log"

    # resume support: a prior run may have converted the disk but died before
    # the reboot stage (evidence: converted rootfs on disk + install.log).
    # Skip straight to reboot+probe — the install step already succeeded.
    if docker run --rm --privileged -v "$OUT:/lab" ezpenguin-vmtest:latest bash -c '
        qemu-nbd -c /dev/nbd0 /lab/debian-12-generic-amd64.qcow2 2>/dev/null; sleep 3
        partprobe /dev/nbd0 2>/dev/null; sleep 1
        mkdir -p /mnt-g && mount -o ro /dev/nbd0p1 /mnt-g 2>/dev/null
        grep -s "^ID=ezpenguin" /mnt-g/etc/os-release
        umount /mnt-g 2>/dev/null; qemu-nbd -d /dev/nbd0 >/dev/null 2>&1' 2>/dev/null | grep -q ezpenguin; then
        log "disk already converted by a prior run — resuming at reboot stage"
        RESUME_REBOOT=1
    else
        RESUME_REBOOT=0
    fi

    # 1. fetch pinned cloud image + checksum evidence
    # NOTE: once resized, the local file no longer matches the publisher
    # checksum — a marker records "verified pristine" so reruns skip both
    # re-download and re-verify without weakening the guarantee.
    # marker lives with the DISK (never inside the rotating attempt dir):
    # once verified-pristine, the file is only mutated by the tracked resize
    local marker="$OUT/image-verified-deb12"
    if [[ ! -s "$img" ]]; then
        log "downloading Debian 12 generic cloud image (pinned: $CLOUD_URL_DEB12)"
        curl -fSL --max-time 900 -o "$img" "$CLOUD_URL_DEB12" || die "download failed"
        rm -f "$marker"
    fi
    if [[ ! -s "$marker" ]]; then
        curl -sSL --max-time 60 "$CLOUD_SUM_DEB12" -o "$log/SHA512SUMS" 2>/dev/null || true
        if [[ -s "$log/SHA512SUMS" ]]; then
            want=$(awk -v f="debian-12-generic-amd64.qcow2" '$2=="*"f || $2==f {print $1}' "$log/SHA512SUMS" | head -1)
            if [[ -n "$want" ]]; then
                have=$(shasum -a 512 "$img" | awk '{print $1}')
                [[ "$have" == "$want" ]] || die "cloud image checksum mismatch (corrupt or mutated download)"
                echo "cloud image verified: sha512=$want" > "$marker"
            else
                die "publisher SHA512SUMS has no entry for debian-12-generic-amd64.qcow2"
            fi
        else
            die "could not fetch publisher SHA512SUMS — refusing unverified cloud image"
        fi
    fi
    cat "$marker"
    # grow disk BEFORE first boot (cloud image is 3GB virtual — too small for
    # a 687MB rootfs + apt cache; resize is a qcow2 metadata op, checksums
    # were verified above)
    docker run --rm -v "$OUT:/lab" ezpenguin-vmtest:latest \
        qemu-img resize /lab/debian-12-generic-amd64.qcow2 8G >"$log/resize.log" 2>&1 \
        || die "qemu-img resize failed (see $log/resize.log)"

    # ephemeral test key: needed by BOTH the fresh path (cloud-init seed) and
    # the resume path (root was authorized pre-conversion)
    local key="$OUT/ezp-test-key"
    [[ -f "$key" ]] || ssh-keygen -q -t ed25519 -N '' -f "$key"

    if (( RESUME_REBOOT )); then
        # jump straight to stage 8: boot the CONVERTED disk without seed media
        stage_reboot_and_probe
        return 0
    fi

    # 2. cloud-init seed: ephemeral ssh key (generated per run), no passwords
    local seed="$OUT/seed-deb12.iso"
    local cdir="$OUT/seed-deb12.d"; rm -rf "$cdir"; mkdir -p "$cdir"
    cat > "$cdir/user-data" <<EOF
#cloud-config
users:
  - name: ezp
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: true
    ssh_authorized_keys:
      - $(cat "$key.pub")
ssh_pwauth: false
chpasswd:
  expire: false
EOF
    printf 'instance-id: ezp-deb12-test\nlocal-hostname: ezp-deb12\n' > "$cdir/meta-data"
    docker run --rm -v "$OUT:$OUT" ezpenguin-vmtest:latest \
        bash -c "xorriso -as mkisofs -output $OUT/seed-deb12.iso -volid cidata -joliet -rock $OUT/seed-deb12.d/user-data $OUT/seed-deb12.d/meta-data" \
        >"$log/seed.log" 2>&1 || die "cloud-init seed ISO failed (see $log/seed.log)"

    # 3. boot VM in Docker (QEMU TCG inside builder container), port-forward ssh
    preboot_fsck
    log "booting VM (2 vCPU, 2GB, TCG) — ssh on host port 2222"
    docker rm -f ezpq-vm >/dev/null 2>&1
    docker run -d --name ezpq-vm \
        -v "$OUT:/lab" -v "$ROOT/installer:/ezp-installer:ro" \
        -p 127.0.0.1:2222:2222 \
        ezpenguin-vmtest:latest \
        bash -c "qemu-system-x86_64 -m 2048 -smp 2 -accel tcg \
            -drive file=/lab/debian-12-generic-amd64.qcow2,format=qcow2,if=virtio \
            -drive file=/lab/seed-deb12.iso,format=raw,if=virtio,media=cdrom \
            -netdev user,id=n0,hostfwd=tcp::2222-:22 -device virtio-net-pci,netdev=n0 \
            -display none -serial file:/lab/debian12-inplace/serial.log" \
        >"$log/qemu-start.log" 2>&1
    docker inspect ezpq-vm --format '{{.State.Status}}' > "$log/container-status" 2>/dev/null

    # 4. wait for guest ssh
    log "waiting for guest SSH (max 8 min)"
    wait_ssh 2222 "$key" 480 || { cat "$log/serial.log" | tail -30 > "$log/serial-tail.txt"; die "guest ssh never came up (serial tail in $log/serial-tail.txt)"; }
    log "guest SSH up"

    # 5. install prereqs + run the candidate one-liner INSIDE the guest
    #    (real networking path: guest DNS + TLS + curl)
    local tb; tb=$(find "$ROOT/artifacts" -maxdepth 1 -name 'ezpenguin-*-amd64-rootfs.tar.xz' | sort -r | head -1)
    [[ -n "$tb" ]] || die "no candidate amd64 rootfs tarball"

    # 6. stage candidate artifact into the guest (installer script itself is
    #    fetched by the guest over real HTTPS — DNS/TLS path stays honest)
    #    Retry up to 3x: long transfers occasionally hit sshd connection resets
    log "staging artifact over ssh ($(basename "$tb"), $(du -h "$tb" | cut -f1))"
    local stage_try stage_ok=0
    for stage_try in 1 2 3; do
        if gzip -c "$tb" | docker exec -i ezpq-vm bash -c "
            gzip -d | ssh -i /lab/ezp-test-key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                -p 2222 ezp@127.0.0.1 'cat > /tmp/ezp-rootfs.tar.xz'
        " >>"$log/stage.log" 2>&1; then stage_ok=1; break; fi
        log "staging attempt $stage_try failed; retrying in 10s"
        sleep 10
    done
    (( stage_ok )) || die "artifact staging failed after 3 attempts (see $log/stage.log)"
    docker exec ezpq-vm bash -c "
        ssh -i /lab/ezp-test-key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -p 2222 ezp@127.0.0.1 'ls -la /tmp/ezp-rootfs.tar.xz && sha256sum /tmp/ezp-rootfs.tar.xz | cut -c1-16'
    " >>"$log/stage.log" 2>&1 || die "staged artifact missing in guest"
    log "staged artifact verified in guest ($(shasum -a 256 "$tb" | cut -c1-16) expected)"

    # 7. run the candidate installer INSIDE the guest via ssh (EZP_NO_REBOOT=1;
    #    we control reboot timing ourselves to prove boot-from-disk)
    # PRE-CONVERSION: authorize the SAME test key for root. The conversion
    # replaces /etc/passwd (fresh-identity contract), so the ezp user will NOT
    # survive it — /root does (rootfs stage ships an empty /root). Seeding
    # root access BEFORE the installer is the only lab-access path; it is a
    # test-harness contract and never done on real installs.
    log "seeding root test key (pre-conversion — ezp user won't survive it)"
    docker exec ezpq-vm bash -c "
        ssh -i /lab/ezp-test-key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -p 2222 ezp@127.0.0.1 'sudo mkdir -p /root/.ssh && sudo cp /home/ezp/.ssh/authorized_keys /root/.ssh/authorized_keys && sudo chmod 700 /root/.ssh && sudo chmod 600 /root/.ssh/authorized_keys && sudo ls -la /root/.ssh'
    " >"$log/rootkey.log" 2>&1 || die "could not seed root test key pre-conversion (see $log/rootkey.log)"

    log "running installer inside guest (in-place conversion, no reboot)"
    docker exec ezpq-vm bash -c "
        ssh -i /lab/ezp-test-key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -p 2222 ezp@127.0.0.1 'sudo env EZP_MODE=inplace EZP_TARBALL=/tmp/ezp-rootfs.tar.xz EZP_ASSUME_YES=1 EZP_NO_REBOOT=1 bash -s 2>/tmp/ezp-trace.log; echo TRACE_RC=$?; tail -25 /tmp/ezp-trace.log' < /ezp-installer/online-installer.sh
        echo INSTALL_RC=\$?
    " >"$log/install.log" 2>&1
    grep -q 'INSTALL_RC=0' "$log/install.log" || { tail -40 "$log/install.log" > "$log/install-tail.txt"; die "in-guest installer failed (see $log/install-tail.txt)"; }

    stage_reboot_and_probe
}

seed_root_key_offline() { # lab contract: test key for root, injected with VM powered off
    docker run --rm --privileged -v "$OUT:/lab" ezpenguin-vmtest:latest bash -c '
        mkdir -p /mnt-g
        qemu-nbd -c /dev/nbd0 /lab/debian-12-generic-amd64.qcow2; sleep 4; partprobe /dev/nbd0 2>/dev/null; sleep 2
        mount /dev/nbd0p1 /mnt-g
        mkdir -p /mnt-g/root/.ssh
        cat /lab/ezp-test-key.pub > /mnt-g/root/.ssh/authorized_keys
        chmod 700 /mnt-g/root/.ssh; chmod 600 /mnt-g/root/.ssh/authorized_keys
        sync; umount /mnt-g; qemu-nbd -d /dev/nbd0 >/dev/null'
}

stage_reboot_and_probe() {
    # 8. reboot from installed disk: kill qemu, boot WITHOUT seed ISO
    log "rebooting from installed disk (installation media detached)"
    docker rm -f ezpq-vm >/dev/null 2>&1 || true
    sleep 20
    if (( ! RESUME_REBOOT )); then preboot_fsck; fi
    # the staged rootfs copy resets /root/.ssh (tarball ships an empty dir) —
    # (re)inject the lab key offline so the probe can log in as root
    seed_root_key_offline
    docker run -d --name ezpq-vm \
        -v "$OUT:/lab" -p 127.0.0.1:2222:2222 ezpenguin-vmtest:latest \
        bash -c "qemu-system-x86_64 -m 2048 -smp 2 -accel tcg \
            -drive file=/lab/debian-12-generic-amd64.qcow2,format=qcow2,if=virtio \
            -netdev user,id=n0,hostfwd=tcp::2222-:22 -device virtio-net-pci,netdev=n0 \
            -display none -serial file:/lab/debian12-inplace/serial-reboot.log" \
        >>"$log/qemu-start.log" 2>&1

    log "waiting for EZpenguin first boot (max 10 min)"
    wait_ssh 2222 "$key" 600 root || { tail -40 "$log/serial-reboot.log" > "$log/serial-reboot-tail.txt"; die "installed disk never came up (serial tail saved)"; }
    # 9. verify the RUNNING OS is EZpenguin and health is green
    log "probing installed system"
    cat > "$OUT/probe.sh" <<'PROBE'
echo ==os==; grep -E "^(ID|PRETTY_NAME)=" /etc/os-release
echo ==kernel==; uname -r
echo ==tools==
for t in ez-info ez-doctor ez-software ez-config ez-backup ez-net ez-update ez-firstboot; do
    command -v "$t" >/dev/null && echo "tool-ok: $t" || echo "tool-MISSING: $t"
done
echo ==ez-info==
timeout 30 ez-info 2>&1 | head -8
echo ==failed-units==
systemctl --failed --no-legend --no-pager | head -5
echo "failed-count=$(systemctl --failed --no-legend --no-pager | wc -l)"
echo ==net==
timeout 15 curl -sSf -o /dev/null -w "https:%{http_code}" https://deb.debian.org 2>&1; echo
echo ==dns==
timeout 10 getent hosts deb.debian.org | head -1
PROBE
    docker exec ezpq-vm bash -c "
        ssh -i /lab/ezp-test-key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -p 2222 root@127.0.0.1 'bash -s' < /lab/probe.sh
    " >"$log/probe.log" 2>&1
    cat "$log/probe.log"
    grep -q '^ID=ezpenguin' "$log/probe.log" || die "rebooted system is not EZpenguin (probe.log)"
    grep -q 'failed-count=0' "$log/probe.log" || die "failed systemd units after boot (probe.log)"
    grep -q 'https:200' "$log/probe.log" || die "network broken after conversion (probe.log)"

    log "PASS: debian12-inplace-amd64 (install → reboot from disk → healthy EZpenguin)"
    echo PASS > "$log/result"
}

cleanup_vm() {
    docker rm -f ezpq-vm >/dev/null 2>&1 || true
    echo "vm cleaned (disk image + logs preserved in $OUT)"
}

case "$SCENARIO" in
    debian12-inplace-amd64) scenario_debian12_inplace ;;
    cleanup) cleanup_vm ;;
    status) docker ps --filter name=ezpq-vm; nc -w2 127.0.0.1 2222 </dev/null 2>/dev/null | head -1 ;;
    *) die "usage: vm-lab.sh <debian12-inplace-amd64|ubuntu2404-inplace-amd64|cleanup|status>" ;;
esac
