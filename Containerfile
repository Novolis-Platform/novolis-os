# Novolis OS — OCI image from Debian rootfs.
#
# Preferred build (works on Windows Podman Desktop + Linux):
#   pwsh -File d:\novolis\novolis-os\scripts\Build-PodmanImage.ps1
#
# That runs mmdebstrap inside a privileged builder container, then imports
# this runtime image. Direct `podman build` of this file expects a prebuilt
# rootfs tarball at artifacts/novolis-os-rootfs.tar.zst (CI rootfs job).

ARG ROOTFS_ARCHIVE=artifacts/novolis-os-rootfs.tar.zst

FROM docker.io/library/ubuntu:24.04 AS unpack
RUN apt-get update -qq \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends zstd \
 && rm -rf /var/lib/apt/lists/*
ARG ROOTFS_ARCHIVE
COPY ${ROOTFS_ARCHIVE} /tmp/rootfs.tar.zst
# Skip device nodes (mknod needs privileges in rootless build).
RUN mkdir -p /out \
 && tar -I zstd -xf /tmp/rootfs.tar.zst -C /out \
      --exclude='./dev' --exclude='./proc' --exclude='./sys' \
 && mkdir -p /out/dev /out/proc /out/sys \
 && rm -f /tmp/rootfs.tar.zst

FROM scratch
COPY --from=unpack /out/ /
ENV DOTNET_ROOT=/usr/share/dotnet \
    PATH=/usr/share/dotnet:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
WORKDIR /
CMD ["/usr/bin/dotnet", "--info"]
