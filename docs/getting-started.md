# Getting started

## Prerequisites

- **QEMU** (`qemu-system-x86_64`) — GUI / primary path ([vm.md](vm.md))
- **Podman** — optional console smoke ([podman.md](podman.md))
- Or Linux with `mmdebstrap`, `zstd`, `e2fsprogs` for native builds

## Verify allowlists

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Verify-PackageBudget.ps1
```

## GUI in QEMU (primary)

Single profile includes UI libraries + cage. Build once, then run:

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Build-Appliance.ps1
pwsh -File d:\novolis\novolis-os\scripts\Run-Qemu.ps1
```

You should see the installed Avalonia app (default smoke, or whatever you published into `artifacts/app-publish`).

Real hardware / OVMF validation: flash or run the UEFI hybrid ([iso.md](iso.md)):

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Run-Iso.ps1
```

Install **GeoPolity** from novolis-apps:

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Build-Appliance.ps1 `
  -AppProject d:\novolis\novolis-apps\src\GeoPolity\GeoPolity.csproj
pwsh -File d:\novolis\novolis-os\scripts\Run-Qemu.ps1
```


## Optional: Podman console

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Build-PodmanImage.ps1
pwsh -File d:\novolis\novolis-os\scripts\Run-Podman.ps1
```

Same package set; no DRM/Wayland seat — console only.

## WSL2

Extract `artifacts/novolis-os-rootfs.tar.zst` and `wsl --import` if you want the userspace under WSLg.
