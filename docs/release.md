# Release

## Versioning

Images are versioned by **git tag** and CI run, not NuGet.

| Artifact | Produced by | When |
|----------|-------------|------|
| `novolis-os-rootfs.tar.zst` | `Build-Rootfs.ps1` / `merge.yml` | Every merge that touches manifests, profiles, or scripts |
| `novolis-os.qcow2` | `Build-Appliance.ps1` | Same, when the appliance job succeeds |

Tag format: `vYYYY.M.D` or `v0.1.0` — attach artifacts to a GitHub Release manually or via `workflow_dispatch`.

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
