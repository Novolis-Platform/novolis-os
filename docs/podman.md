# Podman

Build and run **Novolis OS** as an OCI container with Podman (Windows Podman Desktop or Linux).

## Build + smoke

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Build-PodmanImage.ps1
```

This:

1. Verifies package allowlists
2. Runs `scripts/build-rootfs.sh` inside a **privileged** `ubuntu:24.04` container (`mmdebstrap`)
3. Builds `localhost/novolis-os:latest` from [`Containerfile`](../Containerfile)
4. Smokes with `dotnet --list-runtimes` (must show .NET 10)

Reuse an existing rootfs artifact:

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Build-PodmanImage.ps1 -SkipRootfsBuild
```

## Run

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Run-Podman.ps1
pwsh -File d:\novolis\novolis-os\scripts\Run-Podman.ps1 -Interactive -Command /bin/dash
pwsh -File d:\novolis\novolis-os\scripts\Run-Podman.ps1 -Command /usr/bin/dotnet,--info
```

Bind-mount a published app and execute it:

```powershell
podman run --rm -v d:/apps/MyApp:/app:ro localhost/novolis-os:latest /usr/bin/dotnet /app/MyApp.dll
```

UI apps need a Wayland/X11 socket from the host (WSLg, nested compositor, etc.) — the image ships client libraries only.

## Containerfile-only

When `artifacts/novolis-os-rootfs.tar.zst` already exists:

```powershell
podman build -t localhost/novolis-os:latest -f d:\novolis\novolis-os\Containerfile d:\novolis\novolis-os
podman run --rm localhost/novolis-os:latest /usr/bin/dotnet --list-runtimes
```
