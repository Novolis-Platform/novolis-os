# VM (QEMU) — primary Novolis OS path

**GUI needs a real display.** Use QEMU. Podman/Docker are console-only.

Two boot modes:

| Script | Firmware | Disk | When |
|--------|----------|------|------|
| `Run-Qemu.ps1` | none (kernel-direct) | `novolis-os.qcow2` | Fast dogfood / GUI smoke |
| `Run-Iso.ps1` | OVMF UEFI | `novolis-os.iso` | Validate real-hardware boot path |
| `Run-HyperV.ps1` | Hyper-V Gen2 UEFI | `novolis-os-uefi.vhdx` | Windows host Hyper-V |

Real USB flash: [iso.md](iso.md).

## Build

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Build-Appliance.ps1
```

## Run (kernel-direct)

Install [QEMU](https://www.qemu.org/) (Windows installer usually lands under `C:\Program Files\qemu\` — `Run-Qemu.ps1` finds it).

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Run-Qemu.ps1
```

Boots via `-kernel`/`-initrd` into systemd → **cage** → app under `/opt/novolis/app` (Avalonia).

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Run-Qemu.ps1 -MemoryMb 4096 -Display gtk
```

## Run (UEFI ISO)

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Run-Iso.ps1
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

`Run-Qemu.ps1` also 9p-mounts `artifacts/app-publish` when present (`novolis.app=9p`). Rebuild the appliance (or re-flash ISO) to bake the app into UEFI media.

## Artifacts

| File | Role |
|------|------|
| `artifacts/novolis-os.qcow2` | Root disk for kernel-direct (`LABEL=novolisos`) |
| `artifacts/novolis-os.iso` | UEFI GPT hybrid (flash / OVMF) |
| `artifacts/novolis-os-uefi.img` | Same bytes as the ISO |
| `artifacts/boot/vmlinuz` | Kernel (kernel-direct) |
| `artifacts/boot/initrd.img` | Initrd |
| `artifacts/boot/cmdline.txt` | `root=LABEL=novolisos …` |
| `artifacts/app-publish/` | Host-published Avalonia app installed to `/opt/novolis/app` |
