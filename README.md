<!-- novolis-marketing:start -->
<p align="center">
  <a href="https://github.com/Novolis-Platform">
    <img src="https://raw.githubusercontent.com/Novolis-Platform/.github/main/brand/logo-brand-transparent.svg" width="360" alt="Novolis"/>
  </a>
</p>

<p align="center">
  <strong>Novolis OS</strong><br/>
  Minimal Debian runtime for Novolis apps (.NET 10, Avalonia &amp; Raylib libs, no desktop environment).
</p>

<p align="center">
  <a href="https://github.com/Novolis-Platform/novolis-os/actions"><img src="https://img.shields.io/github/actions/workflow/status/Novolis-Platform/novolis-os/merge.yml?branch=main&label=merge&logo=github" alt="merge"/></a>
  <a href="https://github.com/Novolis-Platform"><img src="https://img.shields.io/badge/org-Novolis--Platform-111827" alt="org"/></a>
</p>

<p align="center">
  <a href="https://github.com/Novolis-Platform/.github/blob/main/profile/README.md">Org landing</a>
  ·
  <a href="https://github.com/Novolis-Platform/novolis-governance">Governance</a>
</p>

---
<!-- novolis-marketing:end -->

# novolis-os

Custom **minimal** Linux runtime for the Novolis platform:

- **.NET 10** runtime (no SDK)
- Shared libraries for **Avalonia** and **Raylib** (X11/Wayland clients, Mesa, fonts, ICU, ALSA)
- **No** GNOME/KDE/XFCE, browsers, Pulse/PipeWire, or build toolchain

Minimalism is gated by `manifests/` allowlists and `scripts/Verify-PackageBudget.ps1`.

## Profiles

| Profile | Script | Artifact |
|---------|--------|----------|
| Podman OCI | `scripts/Build-PodmanImage.ps1` | `localhost/novolis-os:latest` |
| Rootfs | `scripts/Build-Rootfs.ps1` / `scripts/build-rootfs.sh` | `artifacts/novolis-os-rootfs.tar.zst` |
| Appliance | `scripts/Build-Appliance.ps1` | `artifacts/novolis-os.qcow2` |

## Quick commands

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Verify-PackageBudget.ps1
pwsh -File d:\novolis\novolis-os\scripts\Build-PodmanImage.ps1
pwsh -File d:\novolis\novolis-os\scripts\Run-Podman.ps1
```

Podman builds the rootfs in a privileged Ubuntu container (works on Windows Podman Desktop). Native Linux host builds use `Build-Rootfs.ps1`.

## Docs

- [Getting started](docs/getting-started.md)
- [Podman](docs/podman.md)
- [Design](docs/design.md)
- [Runtime surface](docs/runtime-surface.md)
- [Release](docs/release.md)
