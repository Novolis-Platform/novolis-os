# Novolis OS — OCI image: Debian rootfs + default HelloNovolisOs application.
#
#   pwsh -File d:\novolis\novolis-os\scripts\Build-PodmanImage.ps1
#
# Expects artifacts/novolis-os-rootfs.tar.zst (from build-rootfs / CI).

ARG ROOTFS_ARCHIVE=artifacts/novolis-os-rootfs.tar.zst

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS app
WORKDIR /src
COPY smokes/HelloNovolisOs/ ./
RUN dotnet publish HelloNovolisOs.csproj -c Release -o /app/publish --self-contained false -r linux-x64 /p:UseAppHost=false

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
COPY --from=app /app/publish/ /opt/novolis/hello/
ENV DOTNET_ROOT=/usr/share/dotnet \
    PATH=/usr/share/dotnet:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    DOTNET_NOLOGO=1 \
    DOTNET_CLI_TELEMETRY_OPTOUT=1
WORKDIR /opt/novolis/hello
ENTRYPOINT ["/usr/bin/dotnet", "/opt/novolis/hello/HelloNovolisOs.dll"]
CMD []
