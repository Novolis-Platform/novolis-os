# Design

## Purpose

**Novolis OS** is a single Debian (glibc) image for running Novolis apps — Avalonia, Raylib, headless .NET — without a desktop environment or SDK.

One profile (`profiles/default.yaml`) keeps UI + boot stack together so QEMU GUI works without juggling variants.

## Deliverables

| Artifact | Role |
|----------|------|
| `novolis-os-rootfs.tar.zst` | Full userspace (UI libs + kernel packages as installed) |
| `novolis-os.qcow2` + `boot/*` | QEMU kernel-direct boot → systemd → cage → Avalonia smoke |
| Podman OCI (optional) | Same rootfs + console Hello entrypoint |

## Why Debian glibc

Official .NET Linux RIDs and Avalonia/Raylib natives target glibc.

## Package policy

- Explicit packages under `manifests/*.txt`, composed by `profiles/default.yaml`
- `mmdebstrap --variant=minbase`, no APT recommends
- Hard excludes: `manifests/excludes.txt`
- Budgets: ≤80 explicit, ≤280 resolved, ≤900 MiB `.tar.zst`

## UI / boot

No GNOME/KDE. Client libs for Avalonia/Raylib; appliance path uses **seatd** + **cage** and defaults to `graphical.target` with **HelloNovolisOsGui**.

## .NET

Runtime 10 from the official tarball (`dotnet-install.sh`), not Microsoft apt (Debian 13+ sqv rejects that feed’s SHA1-bound key).
