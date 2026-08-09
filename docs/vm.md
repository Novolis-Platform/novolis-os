# VM (QEMU GUI appliance)

Podman/Docker are fine for headless runtime checks. **GUI (Avalonia / Raylib) needs a real display** — use the QEMU appliance.

## What you get

| Artifact | Role |
|----------|------|
| `artifacts/novolis-os.qcow2` | Root filesystem (ext4, `LABEL=novolisos`) |
| `artifacts/boot/vmlinuz` | Kernel for QEMU `-kernel` |
| `artifacts/boot/initrd.img` | Initrd |
| `artifacts/boot/cmdline.txt` | `root=LABEL=novolisos …` |

On boot, systemd reaches `graphical.target` and starts **cage** + **HelloNovolisOsGui** (Avalonia).

No GRUB/ESP in v1 — QEMU boots via `-kernel`/`-initrd`. That is intentional so GUI works without a full installer story. Hyper-V needs a bootloader (not wired yet).

## Build

Windows (Podman Desktop) or Linux:

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Build-Appliance.ps1
```

Needs network (Debian packages + NuGet for Avalonia). First build is slow.

## Run (QEMU)

Install [QEMU](https://www.qemu.org/) so `qemu-system-x86_64` is on `PATH`.

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Run-Qemu.ps1
```

Optional:

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Run-Qemu.ps1 -MemoryMb 4096 -Display gtk
pwsh -File d:\novolis\novolis-os\scripts\Run-Qemu.ps1 -HeadlessSerial   # no GUI window
```

You should see a dark “Novolis OS” Avalonia window under cage.

## Hyper-V

`artifacts/novolis-os.vhdx` may be produced as a disk convert, but **Gen1/Gen2 will not boot** until GRUB/UKI + ESP (or Gen1 MBR) is added. Use QEMU for GUI today.

## Bind your own Avalonia app

After boot (serial console or SSH when you add it), or by rebuilding with your publish output under `/opt/novolis/app` and pointing `novolis-gui.service` at it:

```text
ExecStart=/usr/bin/cage -- /usr/bin/dotnet /opt/novolis/app/YourApp.dll
```

UI libraries (X11/Wayland/Mesa/ALSA) are already in the appliance rootfs.
