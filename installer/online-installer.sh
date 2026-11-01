#!/usr/bin/env bash
# EZpenguin online installer — one-liner.
#
#   bash -c "$(curl -sSfL https://raw.githubusercontent.com/zarigata/EZpenguin/main/installer/online-installer.sh)"
#
# What it does:
#   • Downloads the latest EZpenguin rootfs from GitHub releases
#   • CONTAINERS/VMs (default): in-place conversion — replaces the running
#     system userland with EZpenguin, then reboots (container restart = boot)
#   • BARE METAL: pick a target disk, partition, install, reboot
#
# Environment overrides:
#   EZP_TARBALL=<path-or-url>   skip the release lookup (local testing)
#   EZP_ARCH=<amd64|arm64>      force architecture
#   EZP_NO_REBOOT=1             don't reboot/restart when done
set -euo pipefail
trap 'rc=$?; say "${RED}installer aborted unexpectedly (rc=$rc) at line $LINENO (BASH_COMMAND=${BASH_COMMAND:-?})${RST}" >&2' ERR

REPO="zarigata/EZpenguin"
BOLD='\033[1;36m'; YEL='\033[1;33m'; RED='\033[1;31m'; RST='\033[0m'
say() { printf "%b\n" "$*"; }
die() { printf "%b\n" "${RED}ERROR:${RST} $*" >&2; exit 1; }

banner() {
    printf '%b\n' "${BOLD}
        .--.
       |o_o |
       |:_/ |
      //   \ \\
     (|     | )
    /\"\_   _/\`\\
    \\___)=(___/
     E Z P E N G U I N — online installer${RST}"
}

[[ $EUID -eq 0 ]] || die "run as root"
for cmd in curl tar xz; do command -v "$cmd" >/dev/null || die "missing tool: $cmd"; done

# ---------------------------------------------------------------- detect ----
IN_DOCKER=0
[[ -f /.dockerenv || -f /run/.containerenv ]] && IN_DOCKER=1
grep -qsE 'docker|containerd|kubepods' /proc/1/cgroup 2>/dev/null && IN_DOCKER=1

# idempotent: already converted? (container restart re-runs this installer
# when it was the container command — become a keep-alive instead)
if [[ -f /etc/ezpenguin/.install-source ]] && grep -q '^ID=ezpenguin' /etc/os-release 2>/dev/null; then
    . /etc/os-release
    say "already EZpenguin ($PRETTY_NAME) — nothing to install."
    if [[ "$IN_DOCKER" == 1 ]]; then
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
    *) die "unsupported architecture: $ARCH" ;;
esac
say "architecture: ${BOLD}$ARCH${RST}  environment: ${BOLD}$([[ $IN_DOCKER = 1 ]] && echo container || echo host)${RST}"

# ------------------------------------------------------------- download ----
TMPDIR_EZP=$(mktemp -d)
trap 'command -v rm >/dev/null && { rm -rf "$TMPDIR_EZP" 2>/dev/null || true; }' EXIT
TARBALL="${EZP_TARBALL:-}"

if [[ -z "$TARBALL" ]]; then
    say "locating latest release..."
    REL_JSON="$TMPDIR_EZP/release.json"
    curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" -o "$REL_JSON"
    TAG=$(grep -o '"tag_name": *"[^"]*"' "$REL_JSON" | head -1 | cut -d'"' -f4)
    TARBALL_URL=$(grep -o '"browser_download_url": *"[^"]*-'"$ARCH"'-rootfs.tar.xz"' "$REL_JSON" \
        | head -1 | cut -d'"' -f4)
    [[ -n "$TARBALL_URL" ]] || die "no rootfs asset found for $ARCH in latest release"
    TARBALL="$TMPDIR_EZP/ezpenguin-rootfs.tar.xz"
    say "downloading: ${TARBALL_URL}"
    say "             (tag ${BOLD}${TAG:-?}${RST})"
    curl -fSL --progress-bar -o "$TARBALL" "$TARBALL_URL"
else
    if [[ "$TARBALL" =~ ^https?:// ]]; then
        dl_tmp="$TMPDIR_EZP/ezpenguin-rootfs.tar.xz"
        curl -fSL --progress-bar -o "$dl_tmp" "$TARBALL"; TARBALL="$dl_tmp"
    fi
    [[ -s "$TARBALL" ]] || die "tarball not found: $TARBALL"
fi
say "download OK: $(du -h "$TARBALL" | cut -f1)"

# artifact must be a real xz tarball BEFORE any destructive step — a 404 page
# served as $TARBALL (curl follows the redirect, server returns HTML) would
# otherwise fail only mid-conversion with the system half-replaced (F07).
# ponytail: magic check only; full verification is SHA256SUMS (above).
if ! xz -t "$TARBALL" 2>/dev/null; then
    die "downloaded artifact is not a valid xz archive (wrong URL, 404 page, or corrupt transfer) — nothing was modified"
fi

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

    # trust boundary: only Debian-family systems may be converted in place.
    # Extracting a Debian userland over rpm/apk/pacman systems destroys their
    # package databases and leaves a broken hybrid — refuse BEFORE any change.
    if ! command -v apt-get >/dev/null || ! command -v dpkg >/dev/null; then
        die "in-place conversion requires a Debian-family system (apt-get/dpkg not found).
  this installer only converts Debian/Ubuntu (and derivatives) in place.
  for other distributions use the flashable image or live ISO:
    https://github.com/$REPO/releases"
    fi
    # …and only the doc-promised bases within that family: Linux Mint, Kali,
    # MX & co share apt/dpkg but are out of the qualification matrix — the
    # compatibility contract is Debian 11/12 + Ubuntu 22.04/24.04. Refuse the
    # rest with the same safe, no-changes-made error. NB: mint's os-release
    # impersonates ID=ubuntu — detect it by its own packages instead.
    local base_id=""
    . /etc/os-release 2>/dev/null && base_id="${ID:-}"
    if dpkg-query -W 'mint*' >/dev/null 2>&1; then
        die "in-place conversion supports Debian 11/12 and Ubuntu 22.04/24.04 only (this system: Linux Mint).
  Debian-family derivative out of the qualified bases — refusing safely, nothing was modified.
  for other distributions use the flashable image or live ISO:
    https://github.com/$REPO/releases"
    fi
    case "$base_id" in
        debian|ubuntu) : ;;
        *) die "in-place conversion supports Debian 11/12 and Ubuntu 22.04/24.04 only (this system: ${base_id:-unknown}).
  Debian-family but not a qualified base — refusing safely, nothing was modified.
  for other distributions use the flashable image or live ISO:
    https://github.com/$REPO/releases" ;;
    esac

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
    # NB: findmnt accepts only ONE target arg — a second arg is read as a
    # mountinfo FILE and the whole call fails (rc=1, empty capture). Loop.
    if (( IS_BOOTED )); then
        : > "$TMPDIR_EZP/mounts.txt"
        local mnt_pt
        for mnt_pt in / /boot /boot/efi; do
            findmnt -rn -o TARGET,SOURCE,FSTYPE,OPTIONS "$mnt_pt" 2>/dev/null >> "$TMPDIR_EZP/mounts.txt" || true
        done
        # fallback: kernel mount table (field order /etc/mtab: src mnt fstype opts)
        [[ -s "$TMPDIR_EZP/mounts.txt" ]] || awk '$2=="/"||$2=="/boot"||$2=="/boot/efi"{print $2"\t"$1"\t"$3"\t"$4}' /proc/mounts > "$TMPDIR_EZP/mounts.txt"
        [[ -s "$TMPDIR_EZP/mounts.txt" ]] || cp /proc/mounts "$TMPDIR_EZP/proc-mounts-raw" 2>/dev/null
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
    local PRIV_SNAP="$priv" PLOADER_SNAP="$PLOADER"
    pv() { # execute a priv-toolbox binary immune to the live /lib,/lib64 swap.
           # snapshots (not references) so the EXIT trap can still clean up
           # after this function's locals are gone.
        if [[ -n "$PLOADER_SNAP" ]]; then
            "$PLOADER_SNAP" --library-path "$PRIV_SNAP" "$@"
        else
            LD_LIBRARY_PATH="$PRIV_SNAP${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" "$@"
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
            if [[ "$d" == "$stage/usr" ]]; then
                # /usr holds every running binary (systemd, journald, sshd).
                # cp -a overwrites text pages IN PLACE — a running process
                # that page-faults its old text reads NEW bytes → SIGSEGV.
                # Observed live on a booted Ubuntu VM: journald+PID1 faulted
                # mid-copy and the conversion died halfway. --unlink-first
                # unlinks each FILE before writing it (running procs keep the
                # old inode; new lookups get the new file). Old-OS-only dirs
                # (./bin ./lib64 ./include ./libexec ...) survive as residue —
                # they hold no running code and are merged/flip-handled below.
                tar -C "$d" -cf - . | tar -C /usr --unlink-first -xf - || say "${YEL}note: /usr tar pass reported errors (old-OS-only residue is expected)${RST}"
            else
                # cp -a refuses dir→symlink/dir type mismatches (zoneinfo posix
                # packing). Tolerate those: Debian's tzdata ships /usr/share/
                # zoneinfo/posix as packed symlinks; a diff is cosmetic here.
                cp -a "$d/." "/${d##*/}/" 2>/dev/null || true
            fi
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
        mkdir -p "$dst" || { say "DEBUG: mkdir $dst failed rc=$? (disk full?)"; return 1; }
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
    # the base OS's ifupdown init script survives the /etc merge, but the new
    # userland uses systemd-networkd and ships no `ifup` — left alone,
    # systemd-sysv-generator turns it into a networking.service that FAILS on
    # every boot (0 failed units is the release gate). Mask it declaratively.
    ln -sfn /dev/null /etc/systemd/system/networking.service
    rm -rf "$stage"
    if ! grep -qs '^ID=ezpenguin' /etc/os-release 2>/dev/null; then
        die "extraction did not produce an EZpenguin system (os-release unchanged) — aborting"
    fi

    # container-friendly identity fixes
    cp "$TMPDIR_EZP/resolv.conf" /etc/resolv.conf 2>/dev/null || \
        printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf
    cp "$TMPDIR_EZP/hostname" /etc/hostname 2>/dev/null || true
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
        # a root line is mandatory; without it the system cannot boot.
        # NB: rows look like "<source>  /  <fstype>  <opts>" — the mount
        # target is awk field 2, not a leading "/" (source comes first)
        awk '{print $2}' "$tmp_fstab" | grep -qx '/' \
            || { cp "$TMPDIR_EZP/mounts.txt" /tmp/ezp-mounts.txt 2>/dev/null; cp "$tmp_fstab" /tmp/ezp-fstab.new 2>/dev/null; cp "$TMPDIR_EZP/proc-mounts-raw" /tmp/ezp-procmounts.txt 2>/dev/null; say "DEBUG mounts.txt: $(wc -l < "$TMPDIR_EZP/mounts.txt" 2>/dev/null) rows; fstab.new: $(wc -l < "$tmp_fstab" 2>/dev/null) lines; TMPDIR=$TMPDIR_EZP"; die "could not determine root mount for fstab — aborting"; }
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

    # fresh identity + first-boot on next start
    rm -f /etc/machine-id; : > /etc/machine-id
    rm -f /etc/ezpenguin/.configured
    mkdir -p /etc/ezpenguin
    printf 'online-installer %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > /etc/ezpenguin/.install-source

    # clear apt lists (stale from build container? tarball ships clean — cheap safety)
    rm -rf /var/lib/apt/lists/* 2>/dev/null || true

    # hotpatch: banner.sh tty-detection deadlock in 0.4.0 tarballs (fixed upstream)
    sed -i "s/ || grep -aq 'console' [^ ]*//" /usr/local/lib/ezpenguin/banner.sh 2>/dev/null || true

    # toolbox wrappers reference $priv — drop them BEFORE this scope ends, or
    # the EXIT trap's `rm -rf $TMPDIR_EZP` calls the wrapper after $priv died
    # (set -u abort inside the trap masks the real exit code).
    unset -f cp rm mkdir grep ln find mv readlink pv
    say ""
    say "${BOLD}Conversion complete — this system is now EZpenguin.${RST}"
    . /etc/os-release 2>/dev/null && say "os-release: $PRETTY_NAME"
    say ""
}

# -------------------------------------------------------- bare metal -------
disk_install() {
    say "${YEL}BARE-METAL INSTALL${RST}"
    lsblk -dnpo NAME,SIZE,MODEL,TYPE | awk '$4=="disk"{print "  " $1 "  " $2 "  " $3}' >&2
    read -r -p "Target disk (e.g. /dev/sda — WILL BE ERASED): " TARGET_DISK
    [[ -b "$TARGET_DISK" ]] || die "not a block device: $TARGET_DISK"
    read -r -p "Type 'YES' to wipe $TARGET_DISK: " CONF
    [[ "$CONF" == YES ]] || die "aborted"

    command -v sgdisk >/dev/null || { apt-get update -qq && apt-get install -y -qq gdisk; } || die "install gdisk first"

    swapoff "$TARGET_DISK"* 2>/dev/null || true
    umount "$TARGET_DISK"* 2>/dev/null || true

    if [[ "$ARCH" == "arm64" ]]; then
        sgdisk -Z "$TARGET_DISK"
        sgdisk -n 1:0:+260M -t 1:ef00 -c 1:ESP "$TARGET_DISK"
        sgdisk -n 2:0:0     -t 2:8300 -c 2:root "$TARGET_DISK"
        ESP="${TARGET_DISK}1"; ROOT="${TARGET_DISK}2"
    else
        sgdisk -Z "$TARGET_DISK"
        sgdisk -n 1:0:+1M   -t 1:ef02 -c 1:BIOSBOOT "$TARGET_DISK"
        sgdisk -n 2:0:+260M -t 2:ef00 -c 2:ESP "$TARGET_DISK"
        sgdisk -n 3:0:0     -t 3:8300 -c 3:root "$TARGET_DISK"
        ESP="${TARGET_DISK}2"; ROOT="${TARGET_DISK}3"
    fi
    partprobe "$TARGET_DISK" 2>/dev/null || true; sleep 2
    [[ -e "$ROOT" ]] || ROOT="${TARGET_DISK}p3"; [[ -e "$ESP" ]] || ESP="${TARGET_DISK}p2"

    mkfs.vfat -F32 -n EZP_BOOT "$ESP"
    mkfs.ext4 -L EZP_ROOT -q "$ROOT"

    MNT=$(mktemp -d)
    mount "$ROOT" "$MNT"; mkdir -p "$MNT/boot/efi"; mount "$ESP" "$MNT/boot/efi"
    tar -xJf "$TARBALL" -C "$MNT" --numeric-owner
    printf 'LABEL=EZP_ROOT  /         ext4 defaults,noatime 0 1\nLABEL=EZP_BOOT  /boot/efi vfat defaults 0 2\n' > "$MNT/etc/fstab"
    rm -f "$MNT/etc/machine-id"; : > "$MNT/etc/machine-id"
    rm -f "$MNT/etc/ezpenguin/.configured"
    for d in dev proc sys; do mount --bind "/$d" "$MNT/$d"; done
    ROOT_UUID=$(blkid -s UUID -o value "$ROOT")
    KVER=$(basename "$(ls "$MNT"/boot/vmlinuz-* | sort -V | tail -1)" | sed 's/vmlinuz-//')
    chroot "$MNT" /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin bash -exc '
        if [ "'$ARCH'" = arm64 ]; then
            grub-install --target=arm64-efi --efi-directory=/boot/efi --boot-directory=/boot --no-nvram --removable
        else
            grub-install --target=x86_64-efi --efi-directory=/boot/efi --boot-directory=/boot --no-nvram --removable || true
            grub-install --target=i386-pc --boot-directory=/boot '"$TARGET_DISK"' || true
        fi' >&2
    mkdir -p "$MNT/boot/grub"
    CONSOLE=$([[ "$ARCH" = arm64 ]] && echo 'console=tty0 console=ttyAMA0,115200' || echo 'console=tty0 console=ttyS0,115200n8')
    cat > "$MNT/boot/grub/grub.cfg" <<EOF
set default=0
set timeout=3
menuentry "EZpenguin GNU/Linux" {
    search --no-floppy --fs-uuid --set=root $ROOT_UUID
    linux /boot/vmlinuz-$KVER root=UUID=$ROOT_UUID rw $CONSOLE
    initrd /boot/initrd.img-$KVER
}
EOF
    umount "$MNT/dev" "$MNT/proc" "$MNT/sys" "$MNT/boot/efi" "$MNT"; sync
    say "${BOLD}Installed to $TARGET_DISK — reboot into EZpenguin.${RST}"
}

# ----------------------------------------------------------------- main -----
if [[ "$IN_DOCKER" == 1 || "${EZP_INPLACE:-0}" == 1 ]]; then
    inplace_install
    ACTION="restart this container"
else
    disk_install
    ACTION="reboot"
fi

if [[ "${EZP_NO_REBOOT:-0}" == 1 ]]; then
    say "EZP_NO_REBOOT=1 — skipping $ACTION (run it yourself)"
else
    say "rebooting now: ${BOLD}$ACTION${RST} → boots into EZpenguin, first-boot wizard starts"
    sleep 2
    if [[ "$IN_DOCKER" == 1 ]]; then
        # if this installer IS the container command (PID1), exiting stops the
        # container — the restart policy boots it again into EZpenguin
        # (idempotent guard above turns the re-run into a keep-alive).
        # when run via `docker exec`, signal PID1 as a best effort.
        if [[ $$ -eq 1 ]]; then
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
