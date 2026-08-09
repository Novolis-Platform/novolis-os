# Release

## Versioning

Images are versioned by **git tag** + a **manual** GitHub Actions release — not NuGet, and **not** on every merge.

| Artifact | Produced by | When |
|----------|-------------|------|
| `novolis-os-rootfs.tar.zst` | `Release` workflow | Manual `workflow_dispatch` only |
| `novolis-os.qcow2` | same | same |
| `novolis-os.iso` / `novolis-os-uefi.img` | same (`BUILD_ISO=1`) | same |
| `novolis-os-uefi.vhdx` | `Run-HyperV.ps1` (local convert) | Hyper-V Gen2 on a workstation |

Tag format: `vYYYY.M.D` or `v0.1.0`.

## CI policy

| Workflow | Trigger | What it does |
|----------|---------|----------------|
| `pull-request.yml` | PR → `main` | Package budget only |
| `merge.yml` | push → `main` | Package budget only |
| `release.yml` | **manual** `workflow_dispatch` | Build rootfs + appliance + UEFI ISO, create GitHub Release + assets |

No automatic rootfs/appliance/ISO/Podman image builds on merge.

### Cut a release

1. Actions → **Release** → **Run workflow**
2. Enter tag (e.g. `v0.2.0`); optional prerelease
3. Download assets from the GitHub Release page

```powershell
# Local equivalent (no GitHub Release):
pwsh -File d:\novolis\novolis-os\scripts\Build-Appliance.ps1
```

## No NuGet publish

This repository has `kind: os-image` and publishes **zero** packages. Do not add `dotnet-merge-publish` workflows.

## Appliance first boot

1. systemd starts.
2. Install or copy a Novolis app onto the image (cloud-init / 9p / second disk — operator choice).
3. Run under cage, e.g. `cage -- /usr/bin/dotnet /opt/app/App.dll`.

Default image does not embed product apps.

## Smoke checklist

- [ ] `Verify-PackageBudget.ps1` exit 0
- [ ] Rootfs extracts; `dotnet --info` reports 10.x runtime
- [ ] Headless `dotnet` console app runs
- [ ] Avalonia smoke (optional CI): window opens under cage or nested Wayland
- [ ] Raylib smoke (optional): GL context creates
- [ ] Podman: `Build-PodmanImage.ps1` then `Run-Podman.ps1` prints `app=HelloNovolisOs` / `status=running`
- [ ] QEMU GUI: `Build-Appliance.ps1` then `Run-Qemu.ps1` shows Avalonia HelloNovolisOsGui
- [ ] UEFI ISO: `Run-Iso.ps1` (OVMF) reaches GRUB → cage → app; USB flash boots with Secure Boot off
- [ ] Hyper-V: `Run-HyperV.ps1` (elevated) Gen2 Secure Boot off → GRUB → cage
