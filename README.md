<!-- novolis-marketing:start -->
<p align="center">
  <a href="https://github.com/Novolis-Platform">
    <img src="https://raw.githubusercontent.com/Novolis-Platform/.github/main/brand/logo-brand-transparent.svg" width="360" alt="Novolis"/>
  </a>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/Novolis-Platform/.github/main/brand/banners/novolis-os.svg" width="100%" alt="novolis-os"/>
</p>

<p align="center">
  <strong>Minimal Debian runtime images</strong><br/>
  Allowlisted Debian rootfs and QEMU appliances for running Novolis apps.
</p>

<p align="center">
  <a href="https://novolis-platform.github.io/.github/novolis-os/"><img src="https://img.shields.io/badge/docs-portfolio-0a7ea3" alt="docs"/></a>
  <a href="https://github.com/Novolis-Platform/novolis-os/actions"><img src="https://img.shields.io/github/actions/workflow/status/Novolis-Platform/novolis-os/merge.yml?branch=main&label=merge&logo=github" alt="merge"/></a>
  <a href="https://github.com/orgs/Novolis-Platform/packages?repo_name=novolis-os"><img src="https://img.shields.io/badge/packages-GitHub%20Packages-0a7ea3?logo=nuget" alt="packages"/></a>
  <a href="https://github.com/Novolis-Platform"><img src="https://img.shields.io/badge/org-Novolis--Platform-111827" alt="org"/></a>
</p>

<p align="center">
  <a href="https://novolis-platform.github.io/.github/novolis-os/">Docs</a>
  ·
  <a href="https://nuget.pkg.github.com/Novolis-Platform/index.json"><code>https://nuget.pkg.github.com/Novolis-Platform/index.json</code></a>
  ·
  <a href="https://github.com/Novolis-Platform/.github/blob/main/profile/README.md">Org landing</a>
  ·
  <a href="https://github.com/Novolis-Platform/novolis-governance">Governance</a>
</p>

---
<!-- novolis-marketing:end -->
# novolis-os

**One profile** (`profiles/default.yaml`): Debian minbase + .NET 10 + Avalonia/Raylib UI libs + kernel/systemd/cage + GRUB EFI.

Primary path is **QEMU** (GUI). **UEFI hybrid ISO** for real hardware (flash USB, Secure Boot off). Podman remains optional for console-only smoke.

## Quick start (GUI)

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Build-Appliance.ps1
pwsh -File d:\novolis\novolis-os\scripts\Run-Qemu.ps1
```

Boots into **cage + HelloNovolisOsGui** (Avalonia). Details: [docs/vm.md](docs/vm.md).

## Real hardware (UEFI ISO)

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Build-Appliance.ps1
# Flash artifacts\novolis-os.iso in Rufus DD mode (UEFI, Secure Boot off)
# Or smoke in QEMU+OVMF:
pwsh -File d:\novolis\novolis-os\scripts\Run-Iso.ps1
```

Details: [docs/iso.md](docs/iso.md).

## Optional: Podman console

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Build-PodmanImage.ps1
pwsh -File d:\novolis\novolis-os\scripts\Run-Podman.ps1
```

Uses the same package set (includes kernel bits in the rootfs tarball — accepted size tradeoff).

## Docs

- [Getting started](docs/getting-started.md)
- [VM / QEMU](docs/vm.md)
- [UEFI ISO](docs/iso.md)
- [Podman](docs/podman.md)
- [Design](docs/design.md)
- [Runtime surface](docs/runtime-surface.md)
- [Release](docs/release.md)

