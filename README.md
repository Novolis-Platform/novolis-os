# novolis-os

**One profile** (`profiles/default.yaml`): Debian minbase + .NET 10 + Avalonia/Raylib UI libs + kernel/systemd/cage.

Primary path is **QEMU** (GUI). Podman remains optional for console-only smoke.

## Quick start (GUI)

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Build-Appliance.ps1
pwsh -File d:\novolis\novolis-os\scripts\Run-Qemu.ps1
```

Boots into **cage + HelloNovolisOsGui** (Avalonia). Details: [docs/vm.md](docs/vm.md).

## Optional: Podman console

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Build-PodmanImage.ps1
pwsh -File d:\novolis\novolis-os\scripts\Run-Podman.ps1
```

Uses the same package set (includes kernel bits in the rootfs tarball — accepted size tradeoff).

## Docs

- [Getting started](docs/getting-started.md)
- [VM / QEMU](docs/vm.md)
- [Podman](docs/podman.md)
- [Design](docs/design.md)
- [Runtime surface](docs/runtime-surface.md)
- [Release](docs/release.md)
