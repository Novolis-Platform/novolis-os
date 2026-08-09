# Getting started

## Prerequisites

- **Podman** (recommended on Windows and Linux) — see [podman.md](podman.md)
- Or a Linux host with `pwsh`, `mmdebstrap`, `zstd`, and `debian-archive-keyring`
- Appliance builds also need `qemu-utils` (`qemu-img`) and space for a qcow2

## Verify allowlists

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Verify-PackageBudget.ps1
```

## Build and run with Podman (headless / console)

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Build-PodmanImage.ps1
pwsh -File d:\novolis\novolis-os\scripts\Run-Podman.ps1
```

Produces `localhost/novolis-os:latest` with entrypoint **HelloNovolisOs**. Good for runtime smoke — **not** for Avalonia/Raylib windows. Details: [podman.md](podman.md).

## GUI in a VM (QEMU)

Podman/Docker do not provide a full compositor/GPU seat for Novolis UI apps. Use the appliance:

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Build-Appliance.ps1
pwsh -File d:\novolis\novolis-os\scripts\Run-Qemu.ps1
```

Boots kernel-direct into **cage + HelloNovolisOsGui** (Avalonia). See [vm.md](vm.md).

## Build rootfs on Linux host

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Build-Rootfs.ps1
```

Output: `d:\novolis\novolis-os\artifacts\novolis-os-rootfs.tar.zst`

### WSL2

Extract the tarball into a WSL distro import directory (`wsl --import`), then launch Avalonia/Raylib apps with WSLg or an X/Wayland server.
