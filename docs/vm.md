# VM (QEMU) — primary Novolis OS path

**GUI needs a real display.** Use QEMU. Podman/Docker are console-only.

## Build

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Build-Appliance.ps1
```

## Run

Install [QEMU](https://www.qemu.org/) (Windows installer usually lands under `C:\Program Files\qemu\` — `Run-Qemu.ps1` finds it).

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Run-Qemu.ps1
```

Boots via `-kernel`/`-initrd` into systemd → **cage** → app under `/opt/novolis/app` (Avalonia).

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Run-Qemu.ps1 -MemoryMb 4096 -Display gtk
```

## Install a dogfooding app (ArtillerySimulator)

Publish linux-x64 (needs `Novolis.Raylib.Native` linux runtimes — maintained via raylib `step_02_native`):

```powershell
dotnet publish d:\novolis\novolis-dogfooding\apps\ArtillerySimulator\ArtillerySimulator.csproj `
  -c Release -r linux-x64 --self-contained false /p:UseAppHost=false -o d:\novolis\novolis-os\artifacts\app-publish
Copy-Item d:\novolis\novolis-raylib\src\Novolis.Raylib.Native\runtimes\linux-x64\native\* `
  d:\novolis\novolis-os\artifacts\app-publish\ -Force
pwsh -File d:\novolis\novolis-os\scripts\Install-App.ps1
pwsh -File d:\novolis\novolis-os\scripts\Run-Qemu.ps1
```

`Run-Qemu.ps1` also 9p-mounts `artifacts/app-publish` when present (`novolis.app=9p`).

## Artifacts

| File | Role |
|------|------|
| `artifacts/novolis-os.qcow2` | Root disk (`LABEL=novolisos`) |
| `artifacts/boot/vmlinuz` | Kernel |
| `artifacts/boot/initrd.img` | Initrd |
| `artifacts/boot/cmdline.txt` | `root=LABEL=novolisos …` |
| `artifacts/app-publish/` | Host-published Avalonia app installed to `/opt/novolis/app` |

No GRUB/ESP yet — kernel-direct is enough for QEMU GUI. Hyper-V needs a bootloader later.
