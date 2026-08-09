# Podman

Build and run **Novolis OS** as an OCI container for **console / headless** checks.

For **Avalonia / Raylib GUI**, use the QEMU appliance instead — see [vm.md](vm.md). Containers do not provide a DRM/Wayland seat the way a VM display does.

## Build + smoke

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Build-PodmanImage.ps1
```

This:

1. Verifies package allowlists
2. Builds the rootfs (privileged `ubuntu:24.04` + `mmdebstrap`) unless `-SkipRootfsBuild`
3. Publishes `smokes/HelloNovolisOs` and packs it into `localhost/novolis-os:latest`
4. Runs the app once (`--once`) and checks for `app=HelloNovolisOs` / `status=running`

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Build-PodmanImage.ps1 -SkipRootfsBuild
```

## Run the application

```powershell
# Smoke: start HelloNovolisOs, print banner, exit
pwsh -File d:\novolis\novolis-os\scripts\Run-Podman.ps1

# Stay running (Ctrl+C to stop)
pwsh -File d:\novolis\novolis-os\scripts\Run-Podman.ps1 -Stay

# Same without the helper
podman run --rm localhost/novolis-os:latest --once
podman run --rm -it localhost/novolis-os:latest
```

Shell / override entrypoint:

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Run-Podman.ps1 -Interactive -Command /bin/dash
```

Bind-mount another published app (overrides entrypoint):

```powershell
podman run --rm --entrypoint /usr/bin/dotnet -v d:/apps/MyApp:/app:ro localhost/novolis-os:latest /app/MyApp.dll
```

UI apps need a host Wayland/X11 socket (WSLg, etc.).

## Containerfile-only

When `artifacts/novolis-os-rootfs.tar.zst` already exists:

```powershell
podman build -t localhost/novolis-os:latest -f d:\novolis\novolis-os\Containerfile d:\novolis\novolis-os
podman run --rm localhost/novolis-os:latest --once
```
