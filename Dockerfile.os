# Dockerfile.os — EZpenguin as a runnable Docker OS image (like debian:12).
# Build from repo root after `./build/build.sh image amd64` (or drop any
# release rootfs tarball into artifacts/):
#   docker build -f Dockerfile.os -t ezpenguin .
# Run (interactive shell, motd + ez-* tools):
#   docker run -it --rm ezpenguin
# Optional systemd mode (first-boot wizard will run on tty-less setups only
# via headless config; plain shell remains the default, same as debian:12):
#   docker run -d --name ezp ezpenguin /sbin/init
FROM scratch
ARG TARBALL=artifacts/ezpenguin-1.1.0-amd64-rootfs.tar.xz
ADD ${TARBALL} /
# SIGRTMIN+3 = systemd's shutdown signal, used only when run as PID1 (init mode)
STOPSIGNAL SIGRTMIN+3
CMD ["/bin/bash", "-l"]
LABEL org.opencontainers.image.title="EZpenguin" \
      org.opencontainers.image.description="Lightweight Debian 12 based server OS" \
      org.opencontainers.image.source="https://github.com/zarigata/EZpenguin"
