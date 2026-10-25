# EZpenguin build environment — pinned for reproducibility.
FROM debian:bookworm-slim

# debootstrap needs arch support; live-build only for ISO stage (installed lazily).
RUN apt-get update && apt-get install -y --no-install-recommends \
        debootstrap \
        qemu-user-static \
        binfmt-support \
        qemu-system-x86 \
        qemu-system-arm \
        ovmf \
        qemu-efi-aarch64 \
        dosfstools \
        parted \
        gdisk \
        rsync \
        xorriso \
        squashfs-tools \
        grub2-common \
        grub-pc-bin \
        grub-efi-amd64-bin \
        isolinux \
        syslinux-common \
        mtools \
        xz-utils \
        ca-certificates \
        file \
    && rm -rf /var/lib/apt/lists/*

# Build workspace
WORKDIR /build

# Entrypoint is always a build stage script mounted or copied in
CMD ["/bin/bash"]
