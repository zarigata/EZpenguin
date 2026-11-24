#!/usr/bin/env bash
# EZpenguin Docker helper — one-liner for the prebuilt OS image.
#
#   bash -c "$(curl -sSfL https://raw.githubusercontent.com/zarigata/EZpenguin/main/installer/docker-pull.sh)"
#
# Downloads the docker image tarball for this architecture from GitHub
# Releases, loads it into the local Docker daemon, and starts an
# interactive EZpenguin container. EZP_NO_RUN=1 loads the image only.
set -euo pipefail

REPO="zarigata/EZpenguin"
NAME="ezpenguin"

say() { printf '%b\n' "$*"; }
die() { printf '%b\n' "${RED}ERROR:${RST} $*" >&2; exit 1; }
RED='\033[1;31m'; BOLD='\033[1;36m'; RST='\033[0m'

command -v docker >/dev/null || die "docker not found — install Docker first: https://docs.docker.com/get-docker/"
docker info >/dev/null 2>&1 || die "docker daemon not running"

case "$(uname -m)" in
    x86_64|amd64)  ARCH=amd64 ;;
    aarch64|arm64) ARCH=arm64 ;;
    *) die "unsupported architecture: $(uname -m) (supported: amd64, arm64)" ;;
esac

say "locating latest release..."
API="https://api.github.com/repos/$REPO/releases/latest"
REL_JSON=$(curl -sSfL --max-time 30 "$API") || die "release lookup failed — check network/DNS"
VER=$(grep -o '"tag_name": *"[^"]*"' <<<"$REL_JSON" | head -1 | cut -d'"' -f4)
[[ -n "$VER" ]] || die "release metadata malformed"
ASSET_URL=$(grep -o '"browser_download_url": *"[^"]*docker-'"$ARCH"'.tar.gz"' <<<"$REL_JSON" | head -1 | cut -d'"' -f4)
[[ -n "$ASSET_URL" ]] || die "no docker-$ARCH asset on $VER"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
say "downloading: ${BOLD}${ASSET_URL}${RST}"
curl -fSL --progress-bar --max-time 3600 -o "$TMP/img.tar.gz" "$ASSET_URL" \
    || die "download failed"
say "loading image..."
docker load < "$TMP/img.tar.gz"

# tarballs built before tag standardization carry ezpenguin:<ver>-<arch>
if docker image inspect "$NAME:$VER" >/dev/null 2>&1; then
    TAG="$VER"
elif docker image inspect "$NAME:$VER-$ARCH" >/dev/null 2>&1; then
    TAG="$VER-$ARCH"
else
    die "image loaded but $NAME:$VER / $NAME:$VER-$ARCH not found"
fi

say "${BOLD}EZpenguin $VER image ready ($ARCH).${RST}"
if [[ "${EZP_NO_RUN:-0}" == 1 ]]; then
    say "image loaded — run it with: docker run -it --rm $NAME:$TAG"
else
    exec docker run -it --rm --name ezpenguin "$NAME:$TAG"
fi
