# Getting started

## Prerequisites

- **Podman** (recommended on Windows and Linux) — see [podman.md](podman.md)
- Or a Linux host with `pwsh`, `mmdebstrap`, `zstd`, and `debian-archive-keyring`
- Appliance builds also need `qemu-utils` (`qemu-img`) and space for a qcow2

## Verify allowlists

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Verify-PackageBudget.ps1
```

## Build and run with Podman (Windows + Linux)

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Build-PodmanImage.ps1
pwsh -File d:\novolis\novolis-os\scripts\Run-Podman.ps1
```

Produces `localhost/novolis-os:latest` with entrypoint **HelloNovolisOs**. Smoke runs the app once (`--once`). Details: [podman.md](podman.md).

## Build rootfs on Linux host

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Build-Rootfs.ps1
```

Output: `d:\novolis\novolis-os\artifacts\novolis-os-rootfs.tar.zst`

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
