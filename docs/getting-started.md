# Getting started

## Prerequisites

- Linux host (or CI) with `pwsh`, `mmdebstrap`, `apt-transport-https`, and `zstd`
- Root or unprivileged user namespaces for `mmdebstrap`
- Appliance builds also need `qemu-utils` (`qemu-img`) and space for a qcow2

Windows: run `Verify-PackageBudget.ps1` only. Image builds require Linux.

## Verify allowlists

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Verify-PackageBudget.ps1
```

## Build rootfs

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Build-Rootfs.ps1
```

Output: `d:\novolis\novolis-os\artifacts\novolis-os-rootfs.tar.zst`

### Run with Podman / Docker

```bash
mkdir -p /tmp/novolis-os && tar -I zstd -xf novolis-os-rootfs.tar.zst -C /tmp/novolis-os
podman run --rm -it -v /tmp/novolis-os:/rootfs:ro debian:trixie chroot /rootfs /bin/dash
```

Or import as an OCI rootfs per your runtime’s docs. Bind-mount a published Novolis app and run it with `/usr/bin/dotnet`.

### WSL2

Extract the tarball into a WSL distro import directory (`wsl --import`), then launch Avalonia/Raylib apps with WSLg or an X/Wayland server.

## Build appliance (QEMU)

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Build-Appliance.ps1
```

Output: `d:\novolis\novolis-os\artifacts\novolis-os.qcow2`

```bash
qemu-system-x86_64 -m 2048 -smp 2 -drive file=novolis-os.qcow2,format=qcow2 -device virtio-vga -display gtk
```

Boot drops into a minimal systemd system; start a Novolis app under `cage` (see appliance notes in `docs/release.md`).
