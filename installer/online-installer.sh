#!/usr/bin/env bash
# EZpenguin online installer — DietPi-style one-liner.
#
#   bash -c "$(curl -sSfL https://raw.githubusercontent.com/zarigata/EZpenguin/main/installer/online-installer.sh)"
#
# What it does:
#   • Downloads the latest EZpenguin rootfs from GitHub releases
#   • CONTAINERS (auto/default): in-place conversion — replaces the running
#     system userland with EZpenguin, then reboots (container restart = boot)
#   • VMS/PHYSICAL with EZP_MODE=inplace: converts the running OS in place
#     (systemd+GRUB2 required — validated BEFORE any destructive step)
#   • VMS/PHYSICAL (auto/default): pick a target disk, partition, install, reboot
#
# Contract (documented in README + docs/INSTALLATION.md):
#   Conversion REPLACES the operating system userland with EZpenguin
#   (Debian bookworm). User data in regular directories is preserved;
#   OS-owned files (/etc, /usr, /bin, package databases, bootloader config)
#   become EZpenguin's. This is a replacement, not a package-level merge.
#
# Environment overrides:
#   EZP_TARBALL=<path-or-url>   skip the release lookup (local testing)
#   EZP_ARCH=<amd64|arm64>      force architecture
#   EZP_MODE=<inplace|disk|auto> install mode (auto: container=inplace, else disk)
#   EZP_API_URL=<url>           release API endpoint override (testing)
#   EZP_DOWNLOAD_URL=<url>      asset base URL override (testing)
#   EZP_NO_REBOOT=1             don't reboot/restart when done
#   EZP_ASSUME_YES=1            skip interactive confirms (automation)
set -euo pipefail

REPO="zarigata/EZpenguin"
API_URL="${EZP_API_URL:-https://api.github.com/repos/$REPO/releases/latest}"
DL_BASE="${EZP_DOWNLOAD_URL:-}"
BOLD='\033[1;36m'; YEL='\033[1;33m'; RED='\033[1;31m'; GRN='\033[1;32m'; RST='\033[0m'
say() { printf "%b\n" "$*"; }
die() { printf "%b\n" "${RED}ERROR:${RST} $*" >&2; exit 1; }

banner() {
    printf '%b\n' "${BOLD}
        .--.
       |o_o |
       |:_/ |
      //   \ \
     (|     | )
    /\"\_   _/\`\\
    \\___)=(___/
     E Z P E N G U I N — online installer${RST}"
}

# ------------------------------------------------------------ prereqs -------
[[ $EUID -eq 0 ]] || die "run as root.
  sudo bash -c \"\$(curl -sSfL https://raw.githubusercontent.com/zarigata/EZpenguin/main/installer/online-installer.sh)\""
for cmd in curl tar xz sha256sum; do
    command -v "$cmd" >/dev/null || die "missing tool: $cmd (install it and re-run)"
done

# ------------------------------------------------------------- detect -------
IS_CONTAINER=0
[[ -f /.dockerenv || -f /run/.containerenv ]] && IS_CONTAINER=1
grep -qsE '(docker|containerd|kubepods|/lxc/)' /proc/1/cgroup 2>/dev/null && IS_CONTAINER=1
# systemd running as PID1 = booted OS (VM or physical); containers rarely have it
IS_BOOTED=0
[[ "$(cat /proc/1/comm 2>/dev/null)" == "systemd" ]] && IS_BOOTED=1

MODE="${EZP_MODE:-auto}"
case "$MODE" in
    inplace|disk|auto) ;;
    *) die "EZP_MODE must be inplace, disk or auto (got: $MODE)" ;;
esac
if [[ "$MODE" == "auto" ]]; then
    if (( IS_CONTAINER )); then MODE=inplace; else MODE=disk; fi
fi

# idempotent: already converted? (container restart re-runs this installer
# when it was the container command — become a keep-alive ONLY as PID1;
# a `docker exec` re-run must exit normally, not hang the exec session)
if [[ -f /etc/ezpenguin/.install-source ]] && grep -q '^ID=ezpenguin' /etc/os-release 2>/dev/null; then
    . /etc/os-release
    say "already EZpenguin ($PRETTY_NAME) — nothing to install."
    if (( IS_CONTAINER )) && [[ "$$" -eq 1 ]]; then
        say "keeping container alive (PID1). use: docker exec -it <ctr> bash"
        exec sleep infinity
    fi
    exit 0
fi

banner

ARCH="${EZP_ARCH:-$(uname -m)}"
case "$ARCH" in
    x86_64|amd64) ARCH=amd64 ;;
    aarch64|arm64) ARCH=arm64 ;;
    *) die "unsupported architecture: $ARCH (supported: amd64, arm64)" ;;
esac
env_label="unknown"
if (( IS_CONTAINER )); then env_label="container"
elif (( IS_BOOTED )); then env_label="booted-os"; fi
say "architecture: ${BOLD}$ARCH${RST}  environment: ${BOLD}$env_label${RST}  mode: ${BOLD}$MODE${RST}"

# ------------------------------------------------------------- download -----
TMPDIR_EZP=$(mktemp -d)
trap 'command -v rm >/dev/null && rm -rf "$TMPDIR_EZP"' EXIT
TARBALL="${EZP_TARBALL:-}"
SUMS_FILE=""

if [[ -z "$TARBALL" ]]; then
    say "locating latest release..."
    REL_JSON="$TMPDIR_EZP/release.json"
    curl -sSfL --max-time 30 "$API_URL" -o "$REL_JSON" \
        || die "release lookup failed ($API_URL) — check network/DNS or set EZP_TARBALL"
    TAG=$(grep -o '"tag_name": *"[^"]*"' "$REL_JSON" | head -1 | cut -d'"' -f4)
    [[ -n "$TAG" ]] || die "release metadata malformed (no tag_name) — is $REPO published?"
    # asset name from metadata; full URL from metadata, or joined onto EZP_DOWNLOAD_URL
    ASSET_NAME=$(grep -o '"name": *"[^"]*-'"$ARCH"'-rootfs.tar.xz"' "$REL_JSON" | head -1 | cut -d'"' -f4)
    if [[ -n "$DL_BASE" ]]; then
        [[ -n "$ASSET_NAME" ]] || ASSET_NAME="ezpenguin-$TAG-$ARCH-rootfs.tar.xz"
        TARBALL_URL="${DL_BASE%/}/$ASSET_NAME"
    else
        TARBALL_URL=$(grep -o '"browser_download_url": *"[^"]*-'"$ARCH"'-rootfs.tar.xz"' "$REL_JSON" | head -1 | cut -d'"' -f4)
    fi
    # checksum manifest ships alongside the artifacts (SHA256SUMS)
    if [[ -n "$DL_BASE" ]]; then
        SUMS_URL="$DL_BASE/SHA256SUMS"
    else
        SUMS_URL=$(grep -o '"browser_download_url": *"[^"]*/SHA256SUMS"' "$REL_JSON" | head -1 | cut -d'"' -f4)
    fi
    TARBALL="$TMPDIR_EZP/ezpenguin-rootfs.tar.xz"
    say "downloading: ${TARBALL_URL}"
    say "             (tag ${BOLD}$TAG${RST})"
    curl -fSL --progress-bar --max-time 1800 -o "$TARBALL" "$TARBALL_URL" \
        || die "download failed: $TARBALL_URL"
    if [[ -n "$SUMS_URL" ]]; then
        if curl -sSfL --max-time 60 -o "$TMPDIR_EZP/SHA256SUMS" "$SUMS_URL"; then
            SUMS_FILE="$TMPDIR_EZP/SHA256SUMS"
        else
            say "${YEL}warning: checksum manifest present in metadata but download failed${RST}"
        fi
    else
        say "${YEL}warning: release has no SHA256SUMS asset — integrity NOT verified${RST}"
    fi
else
    if [[ "$TARBALL" =~ ^https?:// ]]; then
        dl_tmp="$TMPDIR_EZP/ezpenguin-rootfs.tar.xz"
        curl -fSL --progress-bar --max-time 1800 -o "$dl_tmp" "$TARBALL" || die "download failed: $TARBALL"
        TARBALL="$dl_tmp"
    fi
    [[ -s "$TARBALL" ]] || die "tarball not found: $TARBALL"
    # local file: verify a sidecar <file>.sha256 if present
    [[ -f "$TARBALL.sha256" ]] && SUMS_FILE="$TARBALL.sha256"
fi

if [[ -n "$SUMS_FILE" ]]; then
    # match on the EXACT asset this run uses (arch+tag) — manifests list
    # every arch's artifact, and picking the first entry silently compared
    # amd64 sums on arm64 hosts (observed: spurious mismatch / false pass)
    base=$(basename "$TARBALL")
    want=$(awk -v b="$base" '{f=$NF; sub(/.*\//, "", f); if (f == b) {print $1; exit}}' "$SUMS_FILE")
    if [[ -n "$want" ]]; then
        have=$(sha256sum "$TARBALL" | awk '{print $1}')
        [[ "$have" == "$want" ]] || die "CHECKSUM MISMATCH
  expected: $want ($base)
  got:      $have
the download is corrupt or tampered — aborting."
        say "${GRN}checksum verified (sha256: $base)${RST}"
    else
        say "${YEL}warning: $base not listed in checksum manifest${RST}"
        [[ "${EZP_STRICT:-0}" == 1 ]] && die "EZP_STRICT=1: unlisted artifact refused"
    fi
elif [[ "${EZP_STRICT:-0}" == 1 ]]; then
    die "EZP_STRICT=1: no checksum manifest available — refusing to install unverified artifact"
fi
say "download OK: $(du -h "$TARBALL" | cut -f1)"

# ------------------------------------------------- in-place mode ------------
inplace_preflight_vm() {
    # VM/physical in-place conversion does real bootloader surgery. Validate
    # the plan BEFORE any destructive step — refusal here is safe, aborting
    # mid-extraction is not.
    (( IS_BOOTED )) || die "in-place on a booted OS requires systemd as PID1.
  detected PID1: $(cat /proc/1/comm 2>/dev/null || echo '?')
  use: EZP_MODE=disk (target-disk install) or run inside a container"
    command -v grub-install >/dev/null || die "grub-install not found in the running system.
  EZpenguin ships its own GRUB, but in-place needs the current bootloader
  layout to remain bootable during conversion.
  use: EZP_MODE=disk instead"
    command -v sgdisk >/dev/null || command -v blkid >/dev/null || true
    # UEFI: need a mounted ESP; BIOS: need the boot disk
    if [[ -d /sys/firmware/efi ]]; then
        findmnt -rn -o TARGET | grep -q '^/boot/efi$\|^/boot$' \
            || die "UEFI boot but no ESP mounted at /boot/efi or /boot — cannot plan bootloader.
  use: EZP_MODE=disk instead"
    fi
}

write_grub_cfg() { # write_grub_cfg <root-device> <console-spec> <outfile>
    local rootdev="$1" console="$2" out="$3"
    local uuid kver
    uuid=$(blkid -s UUID -o value "$rootdev" 2>/dev/null) || uuid=$(findmnt -n -o UUID "$rootdev" 2>/dev/null || true)
    [[ -n "$uuid" ]] || return 1
    kver=$(find /boot -maxdepth 1 -name 'vmlinuz-*' 2>/dev/null | sort -V | tail -1)
    [[ -n "$kver" ]] || return 1
    kver=${kver##*/}
    kver=${kver#vmlinuz-}
    mkdir -p "$(dirname "$out")"
    cat > "$out" <<EOF
set default=0
set timeout=3
serial --unit=0 --speed=115200
terminal_input console serial
terminal_output console serial
menuentry "EZpenguin GNU/Linux" {
    search --no-floppy --fs-uuid --set=root $uuid
    linux /boot/vmlinuz-$kver root=UUID=$uuid rw $console
    initrd /boot/initrd.img-$kver
}
EOF
    grep -q "root=UUID=$uuid" "$out"
}

inplace_install() {
    say "${YEL}IN-PLACE CONVERSION${RST} — this replaces the running system userland."
    say "contract: user data in /home, /srv, /opt, /var/local is kept; OS files become EZpenguin."

    # trust boundary: only Debian-family systems may be converted in place.
    # Extracting a Debian userland over rpm/apk/pacman systems destroys their
    # package databases and leaves a broken hybrid — refuse BEFORE any change.
    if ! command -v apt-get >/dev/null || ! command -v dpkg >/dev/null; then
        die "in-place conversion requires a Debian-family system (apt-get/dpkg not found).
  this installer only converts Debian/Ubuntu (and derivatives) in place.
  for other distributions use the flashable image or live ISO:
    https://github.com/$REPO/releases"
    fi

    if [[ "${EZP_ASSUME_YES:-0}" != 1 && -t 0 ]]; then
        read -r -p "Continue? Type YES: " CONF
        [[ "$CONF" == YES ]] || die "aborted"
    elif [[ "${EZP_ASSUME_YES:-0}" != 1 && "$IS_BOOTED" == 1 ]]; then
        die "in-place conversion on a booted OS requires EZP_ASSUME_YES=1 (non-interactive safety)"
    fi

    if (( ! IS_CONTAINER )); then
        inplace_preflight_vm
    fi

    # preserve container/VM DNS + hostname
    cp -a /etc/resolv.conf "$TMPDIR_EZP/resolv.conf" 2>/dev/null || cp /etc/resolv.conf "$TMPDIR_EZP/resolv.conf" 2>/dev/null || true
    cp -a /etc/hostname   "$TMPDIR_EZP/hostname"    2>/dev/null || true
    # capture mounts BEFORE extraction (needed to restore fstab on booted OS)
    if (( IS_BOOTED )); then
        findmnt -rn -o TARGET,SOURCE,FSTYPE,OPTIONS / /boot /boot/efi 2>/dev/null > "$TMPDIR_EZP/mounts.txt" || true
    fi

    cd /
    say "extracting EZpenguin over /  (a few minutes)"
    # STAGE-THEN-COPY: extracting ./bin and ./lib over a running system kills
    # the extracting tools mid-run when the base libc differs (bullseye glibc
    # 2.31 vs bookworm 2.36 — observed rc=2 with half-replaced binaries).
    # Safe order: unpack everything to a staging dir first (tar never touches
    # the running root), then overlay-copy with cp -a in link-heavy→lib-last
    # order so every tool that runs still finds a working libc.
    local stage d tpath tlib priv
    priv="$TMPDIR_EZP/privbin"
    stage=$(mktemp -d /ezp-stage.XXXXXX) || die "cannot create staging dir"
    # PRIVATE TOOLBOX: the copy loop replaces /bin and /lib. After that, every
    # tool this script runs must be the OLD-OS copy + OLD libc (copied now,
    # before anything is replaced). LD_LIBRARY_PATH pointing at the private
    # dir makes ld.so resolve our private libc first for everything we exec.
    mkdir -p "$priv"
    local tool
    for tool in cp mkdir rm grep cat sh bash sed uname ln find readlink mv; do
        tpath=$(command -v "$tool" 2>/dev/null) || continue
        cp -L "$tpath" "$priv/" 2>/dev/null || true
        for tlib in $(ldd "$tpath" 2>/dev/null | awk '/=> \//{print $3}'); do
            cp -L "$tlib" "$priv/" 2>/dev/null || true
        done
    done
    for tlib in /lib/x86_64-linux-gnu/libc.so.6 /lib64/ld-linux-x86-64.so.2 \
                /lib/aarch64-linux-gnu/libc.so.6 /lib/ld-linux-aarch64.so.1; do
        if [[ -e "$tlib" ]]; then cp -L "$tlib" "$priv/" 2>/dev/null || true; fi
    done
    # EXPLICIT INTERPRETER: priv binaries keep PT_INTERP=/lib64/ld-*.so.2.
    # The usrmerge swap does `rm -rf /lib64`, after which exec'ing them dies
    # with "No such file or directory" (observed on bullseye: the kernel
    # loads the interpreter from disk at every exec, LD_LIBRARY_PATH can't
    # help). Run every priv tool THROUGH the private loader instead.
    local PLOADER=""
    case "$ARCH" in
        arm64) [[ -f "$priv/ld-linux-aarch64.so.1" ]] && PLOADER="$priv/ld-linux-aarch64.so.1" ;;
        *)     [[ -f "$priv/ld-linux-x86-64.so.2" ]] && PLOADER="$priv/ld-linux-x86-64.so.2" ;;
    esac
    pv() { # execute a priv-toolbox binary immune to the live /lib,/lib64 swap
        if [[ -n "$PLOADER" ]]; then
            "$PLOADER" --library-path "$priv" "$@"
        else
            LD_LIBRARY_PATH="$priv${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" "$@"
        fi
    }
    # wrap the risky tools so every later call runs the private, libc-immune copy.
    # NB: bullseye keeps these in /bin — the /bin dir itself is never deleted
    # before merge_dir, only files within it are replaced via rename.
    cp() { pv "$priv/cp" "$@"; }
    rm() { pv "$priv/rm" "$@"; }
    mkdir() { pv "$priv/mkdir" "$@"; }
    grep() { pv "$priv/grep" "$@"; }
    ln() { pv "$priv/ln" "$@"; }
    find() { pv "$priv/find" "$@"; }
    mv() { pv "$priv/mv" "$@"; }
    readlink() { pv "$priv/readlink" "$@"; }
    local tar_rc=0
    tar -xJf "$TARBALL" -C "$stage" --numeric-owner || tar_rc=$?
    if (( tar_rc != 0 )); then
        rm -rf "$stage"
        die "tar extraction failed (rc=$tar_rc) — artifact unusable, nothing changed."
    fi
    [[ -f "$stage/usr/local/bin/ez-firstboot" && -f "$stage/etc/os-release" ]] \
        || { rm -rf "$stage"; die "artifact does not contain an EZpenguin rootfs — aborting"; }

    say "copying staged system onto /"
    # Two base layouts exist:
    #   • usrmerge (bookworm, ubuntu): /bin→usr/bin symlink; copying ./usr/bin
    #     covers everything. Replacing the symlink is atomic (rename).
    #   • split (bullseye): /bin is a REAL dir; /usr/bin may not even exist.
    # Strategy: detect, then copy with unlink-first semantics — overwrite via
    # temp+rename so a running binary keeps its inode (no "Text file busy")
    # and we never delete before the replacement exists.
    local d f
    if [[ -L /bin ]]; then
        # shellcheck disable=SC2114  # symlinks on usrmerge bases
        rm -rf /bin /lib /lib64 /sbin || true
        ln -s usr/bin /bin
        ln -s usr/lib /lib
        ln -s usr/lib64 /lib64
        ln -s usr/sbin /sbin
    fi
    for d in "$stage"/*; do
        case "$d" in
            "$stage"/dev|"$stage"/proc|"$stage"/sys|"$stage"/run|"$stage"/tmp|"$stage"/mnt|"$stage"/media) continue ;;
            "$stage"/etc) continue ;;  # etc last: identity files preserved
            "$stage"/bin|"$stage"/sbin|"$stage"/lib|"$stage"/lib64) continue ;;  # handled below
        esac
        if [[ -d "$d" ]]; then
            # cp -a refuses dir→symlink/dir type mismatches (zoneinfo posix
            # packing). Tolerate those: Debian's tzdata ships /usr/share/
            # zoneinfo/posix as packed symlinks; a diff is cosmetic here.
            cp -a "$d/." "/${d##*/}/" 2>/dev/null || true
        else
            # top-level file (e.g. initrd.img, vmlinuz symlinks) → / is its home
            cp -a "$d" "/${d##*/}" || { rm -rf "$stage"; die "copy of ${d##*/} failed — aborting"; }
        fi
    done
    # merged dirs: copy IN PLACE with rename (busy-safe, atomic per file)
    # ponytail: per-file shell loop over ~4k files in /usr/bin — seconds, not
    # minutes; upgrade path is `cp --remove-destination` when coreutils are
    # guaranteed >= 9.x on the BASE system (they aren't: bullseye ships 8.32).
    merge_dir() { # merge_dir <stage-subdir> <target>
        local src="$1" dst="$2" f
        mkdir -p "$dst"
        while IFS= read -r f; do
            local base="${f##*/}"
            case "$base" in
                '.'|'..') continue ;;
            esac
            if [[ -L "$f" ]]; then
                # symlink: copy the LINK itself, replace atomically via temp
                local tlink
                tlink=$(readlink "$f" 2>/dev/null)
                ln -sfn "$tlink" "$dst/.ezp-l" 2>/dev/null && \
                    mv -Tf "$dst/.ezp-l" "$dst/$base" 2>/dev/null || true
            elif [[ -d "$f" ]]; then
                mkdir -p "$dst/$base"
                cp -a "$f/." "$dst/$base/" 2>/dev/null || true
            else
                # regular file: stage beside target then rename over (busy-safe:
                # running processes keep the old inode; ETXTBSY never fires on rename)
                cp -a "$f" "$dst/.ezp-new" 2>/dev/null || true
                mv -Tf "$dst/.ezp-new" "$dst/$base" 2>/dev/null || true
            fi
        done < <(find "$src" -mindepth 1 -maxdepth 1 2>/dev/null)
        rm -f "$dst/.ezp-new" "$dst/.ezp-l"
    }
    # merged dirs: iterate RESOLVED stage targets. In the stage, ./bin ./lib
    # ./lib64 ./sbin are SYMLINKS to usr/* — find(1) without -L lists the
    # symlink itself and stops, so merge stage/usr/* into /usr/*.
    merge_dir "$stage/usr/bin" /usr/bin
    merge_dir "$stage/usr/sbin" /usr/sbin
    merge_dir "$stage/usr/lib" /usr/lib
    merge_dir "$stage/usr/lib64" /usr/lib64
    # split-layout bases (bullseye): /bin /sbin /lib are REAL dirs holding the
    # OLD libc; the new one lives in /usr/lib. A symlink /lib→usr/lib now that
    # everything new is in /usr/lib: stale 2.31 files are removed and every
    # loader resolves /lib/... through the merged /usr/lib.
    if [[ ! -L /bin ]]; then
        # shellcheck disable=SC2114  # split-layout: replace real dirs with usrmerge symlinks
        rm -rf /lib /lib64 /bin /sbin || true
        ln -s usr/bin /bin
        ln -s usr/lib /lib
        ln -s usr/lib64 /lib64
        ln -s usr/sbin /sbin
    fi
    # /etc last. The tarball's ./etc/resolv.conf is a SYMLINK to
    # /run/systemd/resolve/stub-resolv.conf (dangling in a container).
    # cp -a refuses to write THROUGH a dangling symlink — remove staged
    # identity files up front; the originals survive (we never touch /etc's
    # own copies) and the explicit write below refreshes them.
    local f
    rm -f "$stage/etc/resolv.conf" "$stage/etc/hostname" "$stage/etc/hosts" "$stage/etc/machine-id"
    for f in hostname hosts machine-id; do
        if [[ -e /etc/$f && ! -L /etc/$f ]]; then cp -a /etc/$f "$stage/etc/$f"; fi
    done
    cp -a "$stage/etc/." /etc/ 2>/dev/null || true
    rm -rf "$stage"
    if ! grep -qs '^ID=ezpenguin' /etc/os-release 2>/dev/null; then
        die "extraction did not produce an EZpenguin system (os-release unchanged) — aborting"
    fi

    # container-friendly identity fixes
    cp "$TMPDIR_EZP/resolv.conf" /etc/resolv.conf 2>/dev/null || \
        printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf
    cp "$TMPDIR_EZP/hostname" /etc/hostname 2>/dev/null || true
    local HN
    HN=$(cat /etc/hostname 2>/dev/null || echo ezpenguin)
    printf '127.0.0.1\tlocalhost\n127.0.1.1\t%s\n' "$HN" > /etc/hosts

    if (( IS_CONTAINER )); then
        # no fstab mounts in a container; avoid systemd emergency on systemd-enabled boots
        printf '# EZpenguin (container install — no local mounts)\n' > /etc/fstab
    else
        # booted OS: restore real mounts for /, /boot, /boot/efi (captured pre-extraction)
        local tmp_fstab; tmp_fstab="$TMPDIR_EZP/fstab.new"
        printf '# EZpenguin (in-place conversion)\n' > "$tmp_fstab"
        while IFS=$'\t' read -r tgt src fst _opts; do
            case "$tgt" in
                /)         printf '%s  /         %s  defaults,noatime  0 1\n' "$src" "$fst" ;;
                /boot)     printf '%s  /boot     %s  defaults         0 2\n' "$src" "$fst" ;;
                /boot/efi) printf '%s  /boot/efi %s  defaults         0 2\n' "$src" "$fst" ;;
            esac
        done < "$TMPDIR_EZP/mounts.txt" >> "$tmp_fstab"
        # a root line is mandatory; without it the system cannot boot
        grep -qE '^[^#].*\s+/\s+' "$tmp_fstab" || die "could not determine root mount for fstab — aborting"
        mv "$tmp_fstab" /etc/fstab
        # regenerate bootloader config for the NEW kernel (the old distro's
        # grub.cfg points at its kernel, which we just replaced)
        local rootdev console grub_ok=0 grub_target
        rootdev=$(findmnt -n -o SOURCE / 2>/dev/null)
        if [[ "$ARCH" == arm64 ]]; then
            console='console=tty0 console=ttyAMA0,115200'; grub_target=arm64-efi
        else
            console='console=tty0 console=ttyS0,115200n8'; grub_target=x86_64-efi
        fi
        if command -v grub-install >/dev/null && write_grub_cfg "$rootdev" "$console" /boot/grub/grub.cfg; then
            if [[ -d /sys/firmware/efi ]]; then
                local esp; esp=$(findmnt -n -o TARGET /boot/efi 2>/dev/null || findmnt -n -o TARGET /boot 2>/dev/null || true)
                if [[ -n "$esp" ]] && grub-install --target="$grub_target" \
                     --efi-directory="$esp" --boot-directory=/boot --no-nvram --removable \
                     >/dev/null 2>&1; then
                    grub_ok=1
                fi
            else
                local bootdisk; bootdisk="/dev/$(lsblk -no pkname "$rootdev" 2>/dev/null | head -1)"
                if [[ -n "$bootdisk" ]] && grub-install --target=i386-pc \
                     --boot-directory=/boot "$bootdisk" >/dev/null 2>&1; then
                    grub_ok=1
                fi
            fi
        fi
        (( grub_ok )) || die "bootloader regeneration failed — system is converted but may not boot.
  do NOT reboot; run EZP_MODE=disk from a live medium instead."
        say "${GRN}bootloader regenerated${RST}"
    fi

    # fresh identity + first-boot on next start (priv toolbox still valid here)
    rm -f /etc/machine-id; : > /etc/machine-id
    rm -f /etc/ezpenguin/.configured
    printf 'online-installer %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > /etc/ezpenguin/.install-source

    # clear apt lists (stale from the previous distro — tarball ships clean, cheap safety)
    rm -rf /var/lib/apt/lists/* 2>/dev/null || true

    # hotpatch: banner.sh tty-detection deadlock in 0.4.0 tarballs (fixed upstream)
    sed -i "s/ || grep -aq 'console' [^ ]*//" /usr/local/lib/ezpenguin/banner.sh 2>/dev/null || true

    # toolbox wrappers reference $priv — drop them before scope ends
    unset -f cp rm mkdir grep ln find mv readlink pv
    say ""
    say "${BOLD}Conversion complete — this system is now EZpenguin.${RST}"
    . /etc/os-release 2>/dev/null && say "os-release: $PRETTY_NAME"
    say ""
}

# -------------------------------------------------------- bare metal --------
part_names() { # echo "<ESP> <ROOT>" for a freshly partitioned disk
    local d="$1" esp root
    if [[ "$ARCH" == arm64 ]]; then
        esp="${d}1"; root="${d}2"
        [[ -e "$esp" && -e "$root" ]] || { esp="${d}p1"; root="${d}p2"; }
    else
        esp="${d}2"; root="${d}3"
        [[ -e "$esp" && -e "$root" ]] || { esp="${d}p2"; root="${d}p3"; }
    fi
    [[ -e "$esp" && -e "$root" ]] || return 1
    echo "$esp $root"
}

disk_install() {
    say "${YEL}BARE-METAL INSTALL${RST}"
    command -v lsblk >/dev/null || die "lsblk not found (install util-linux)"
    lsblk -dnpo NAME,SIZE,MODEL,TYPE 2>/dev/null | awk '$4=="disk"{print "  " $1 "  " $2 "  " $3}' >&2
    local TARGET_DISK
    read -r -p "Target disk (e.g. /dev/sda — WILL BE ERASED): " TARGET_DISK
    [[ -b "$TARGET_DISK" ]] || die "not a block device: $TARGET_DISK"
    read -r -p "Type 'YES' to wipe $TARGET_DISK: " CONF
    [[ "$CONF" == YES ]] || die "aborted"

    if ! command -v sgdisk >/dev/null; then
        if command -v apt-get >/dev/null; then
            if ! apt-get update -qq; then die "apt-get update failed — install gdisk manually"; fi
            apt-get install -y -qq gdisk || die "install gdisk first"
        else
            die "sgdisk not found — install gdisk first"
        fi
    fi

    swapoff "$TARGET_DISK"* 2>/dev/null || true
    umount "$TARGET_DISK"* 2>/dev/null || true

    if [[ "$ARCH" == "arm64" ]]; then
        sgdisk -Z "$TARGET_DISK"
        sgdisk -n 1:0:+260M -t 1:ef00 -c 1:ESP "$TARGET_DISK"
        sgdisk -n 2:0:0     -t 2:8300 -c 2:root "$TARGET_DISK"
    else
        sgdisk -Z "$TARGET_DISK"
        sgdisk -n 1:0:+1M   -t 1:ef02 -c 1:BIOSBOOT "$TARGET_DISK"
        sgdisk -n 2:0:+260M -t 2:ef00 -c 2:ESP "$TARGET_DISK"
        sgdisk -n 3:0:0     -t 3:8300 -c 3:root "$TARGET_DISK"
    fi
    partprobe "$TARGET_DISK" 2>/dev/null || true; sleep 2
    local ESP ROOT
    read -r ESP ROOT < <(part_names "$TARGET_DISK") || die "cannot find partitions on $TARGET_DISK"

    command -v mkfs.vfat >/dev/null || die "mkfs.vfat missing (dosfstools)"
    mkfs.vfat -F32 -n EZP_BOOT "$ESP"
    mkfs.ext4 -L EZP_ROOT -q "$ROOT"

    local MNT
    MNT=$(mktemp -d)
    mount "$ROOT" "$MNT"; mkdir -p "$MNT/boot/efi"; mount "$ESP" "$MNT/boot/efi"
    tar -xJf "$TARBALL" -C "$MNT" --numeric-owner || { umount -R "$MNT" || true; die "tar extraction to target failed"; }
    printf 'LABEL=EZP_ROOT  /         ext4 defaults,noatime 0 1\nLABEL=EZP_BOOT  /boot/efi vfat defaults 0 2\n' > "$MNT/etc/fstab"
    rm -f "$MNT/etc/machine-id"; : > "$MNT/etc/machine-id"
    rm -f "$MNT/etc/ezpenguin/.configured"
    for d in dev proc sys; do mount --bind "/$d" "$MNT/$d"; done
    local ROOT_UUID KVER ESP ROOT
    ROOT_UUID=$(blkid -s UUID -o value "$ROOT")
    KVER=$(find "$MNT/boot" -maxdepth 1 -name 'vmlinuz-*' | sort -V | tail -1)
    [[ -n "$KVER" ]] || { umount -R "$MNT" 2>/dev/null || true; die "no kernel found in extracted rootfs"; }
    KVER=${KVER##*/}; KVER=${KVER#vmlinuz-}
    local GRUB_TARGET
    GRUB_TARGET=$([[ "$ARCH" == arm64 ]] && echo arm64-efi || echo x86_64-efi)
    # EFI first; amd64 falls back to i386-pc on the same disk if EFI fails.
    # BOTH failing = unbootable disk → abort (never suppress silently).
    if ! chroot "$MNT" /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin \
            grub-install --target="$GRUB_TARGET" --efi-directory=/boot/efi \
            --boot-directory=/boot --no-nvram --removable >&2; then
        if [[ "$ARCH" == amd64 ]]; then
            chroot "$MNT" /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin \
                grub-install --target=i386-pc --boot-directory=/boot "$TARGET_DISK" >&2 \
                || { umount -R "$MNT" 2>/dev/null || true; die "grub installation failed — target would be unbootable, aborting"; }
        else
            umount -R "$MNT" 2>/dev/null || true
            die "grub (arm64-efi) installation failed — target would be unbootable, aborting"
        fi
    fi
    mkdir -p "$MNT/boot/grub"
    local CONSOLE
    if [[ "$ARCH" == arm64 ]]; then CONSOLE='console=tty0 console=ttyAMA0,115200'; else CONSOLE='console=tty0 console=ttyS0,115200n8'; fi
    cat > "$MNT/boot/grub/grub.cfg" <<EOF
set default=0
set timeout=3
menuentry "EZpenguin GNU/Linux" {
    search --no-floppy --fs-uuid --set=root $ROOT_UUID
    linux /boot/vmlinuz-$KVER root=UUID=$ROOT_UUID rw $CONSOLE
    initrd /boot/initrd.img-$KVER
}
EOF
    grep -q "root=UUID=$ROOT_UUID" "$MNT/boot/grub/grub.cfg" || { umount -R "$MNT" 2>/dev/null || true; die "grub.cfg sanity check failed"; }
    umount "$MNT/dev" "$MNT/proc" "$MNT/sys" "$MNT/boot/efi" "$MNT" 2>/dev/null || true; rm -rf "$MNT"; sync
    say "${BOLD}Installed to $TARGET_DISK — reboot into EZpenguin.${RST}"
}

# ----------------------------------------------------------------- main -----
if [[ "$MODE" == "inplace" ]]; then
    inplace_install
    if (( IS_CONTAINER )); then ACTION="restart this container"; else ACTION="reboot"; fi
else
    disk_install
    ACTION="reboot"
fi

if [[ "${EZP_NO_REBOOT:-0}" == 1 ]]; then
    say "EZP_NO_REBOOT=1 — skipping $ACTION (run it yourself)"
else
    say "rebooting now: ${BOLD}$ACTION${RST} → boots into EZpenguin, first-boot wizard starts"
    sleep 2
    if (( IS_CONTAINER )); then
        if [[ "$$" -eq 1 ]]; then
            exit 0
        else
            kill -TERM 1 2>/dev/null || kill -KILL 1 2>/dev/null || true
            say "if still running: docker restart <container>"
            exit 0
        fi
    else
        systemctl reboot || reboot || true
    fi
fi
