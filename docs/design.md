# Design

## Purpose

**Novolis OS** is a minimal Debian (glibc) runtime image for running Novolis applications — Avalonia desktops, Raylib games, headless .NET services — without a desktop environment or developer toolchain.

Minimal is enforced by allowlists and budgets, not slogans.

## Profiles

| Profile | Artifact | Contains |
|---------|----------|----------|
| `rootfs` | `novolis-os-rootfs.tar.zst` | Userspace + .NET 10 runtime + UI/audio libs |
| `appliance` | `novolis-os.qcow2` | Rootfs + kernel + systemd + seatd + cage |

Apps are **not** baked into the image. Install or bind-mount them separately.

## Why Debian glibc

Official .NET Linux RIDs and Avalonia/Raylib native stacks target glibc. Alpine/musl is out of scope for v1.

## Package policy

- Every explicit package lives under `manifests/*.txt`.
- Builds use `mmdebstrap --variant=minbase` and omit APT recommends.
- Hard excludes: `manifests/excludes.txt` (desktop DEs, browsers, Pulse/PipeWire, SDKs, compilers, docs).
- `scripts/Verify-PackageBudget.ps1` fails CI if allowlists grow past the budget or match an exclude.

### Budgets

| Metric | Cap |
|--------|-----|
| Explicit allowlist packages (rootfs manifests, excluding comments) | 64 |
| Explicit allowlist packages (including appliance.txt) | 80 |
| Resolved packages in a built rootfs (when `artifacts/resolved-packages.txt` present) | 280 |
| Rootfs tarball size (`.tar.zst`) | 900 MiB |

## UI model

No GNOME/KDE/XFCE. The rootfs ships **client libraries** (X11, Wayland, Mesa, fonts, ICU) so Avalonia and Raylib can open windows under an external compositor (WSL, nested, or host Wayland).

The appliance adds **cage** (single-app Wayland kiosk) and **seatd** so a QEMU VM can present one Novolis app fullscreen.

## .NET

`dotnet-runtime-10.0` only (Microsoft package feed). No SDK, no ASP.NET runtime unless a future consumer proves need.
