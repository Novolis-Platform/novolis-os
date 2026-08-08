# Runtime surface

Map of Novolis library layers to OS packages. Pure managed stacks need only the .NET runtime.

| Layer / stack | OS packages | Manifest |
|---------------|-------------|----------|
| Math, Physics, Simulation, Gaming (managed) | `dotnet-runtime-10.0` | `dotnet.txt` |
| ICU / globalization | `libicu76` | `base.txt` |
| TLS | `libssl3t64`, `ca-certificates`, `zlib1g` | `base.txt` |
| Avalonia / Skia | fontconfig, freetype, X11/xcb, Wayland client, `libxkbcommon0`, fonts | `ui-graphics.txt` |
| Avalonia 3D / Silk OpenGL / Raylib | Mesa EGL/GL/GLES, `libdrm2`, `libgbm1`, `libdecor-0-0` | `ui-graphics.txt` |
| Raylib / game audio | `libasound2t64` | `audio-alsa.txt` |
| Appliance display | `cage`, `seatd`, `linux-image-amd64`, `systemd` | `appliance.txt` |

## Explicitly not provided

| Need | Why absent |
|------|------------|
| .NET SDK | Runtime image only |
| PulseAudio / PipeWire | ALSA is enough for Raylib; keeps the graph small |
| Desktop environment | Apps own their windows; cage covers kiosk VM |
| Windows-only voice / Inno | Host those on Windows; not Linux OS scope |

## Adding a package

1. Confirm a Novolis library fails without it (document the failure).
2. Add the exact Debian package name to the right `manifests/*.txt`.
3. Update this table.
4. Run `Verify-PackageBudget.ps1` — stay under budget and clear of `excludes.txt`.
