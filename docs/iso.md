# UEFI hybrid ISO (real hardware)

Persistent GPT media with ESP + GRUB + ext4 root (`LABEL=novolisos`). Same appliance stack as the QEMU qcow (systemd → cage → `/opt/novolis/app`).

## Build

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Build-Appliance.ps1
```

Produces (among other artifacts):

| File | Role |
|------|------|
| `artifacts/novolis-os.iso` | GPT hybrid (identical bytes to `.img`) — flash in **DD** mode |
| `artifacts/novolis-os-uefi.img` | Same image, clearer name for `dd` |
| `artifacts/novolis-os-uefi.vhdx` | Hyper-V Gen2 disk (from `Run-HyperV.ps1`) |

UEFI only — no legacy BIOS. GRUB is **unsigned** → turn **Secure Boot off**.

## Flash to USB

**Rufus / balenaEtcher:** choose the `.iso` or `.img`, use **DD / image** mode (not ISO9660 file copy).

**Linux / WSL:**

```powershell
# Example: replace /dev/sdX with your USB device — destroys all data on it
# dd if=d:/novolis/novolis-os/artifacts/novolis-os.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

## Test in Hyper-V (Generation 2)

Converts the GPT hybrid to VHDX, creates VM **NovolisOS** with **Secure Boot Off**, and opens VM Connect:

```powershell
# Elevated PowerShell required
pwsh -File d:\novolis\novolis-os\scripts\Run-HyperV.ps1
```

Do not attach a qcow-derived disk to Hyper-V. `Run-HyperV.ps1` builds `artifacts/novolis-os-uefi.vhdx` from the UEFI GPT hybrid.

## Test in QEMU (OVMF)

```powershell
pwsh -File d:\novolis\novolis-os\scripts\Run-Iso.ps1
```

Needs QEMU with OVMF/edk2 firmware files. Pass `-OvmfCode` if auto-detect fails.

Day-to-day dogfooding can stay on kernel-direct qcow: [vm.md](vm.md).

## Layout

| Partition | Type | Contents |
|-----------|------|----------|
| 1 | EFI System (FAT32) | `EFI/BOOT/BOOTX64.EFI`, GRUB modules |
| 2 | Linux (ext4 `novolisos`) | Full rootfs + apps |

## Out of scope (v1)

- Secure Boot signing
- Legacy BIOS
- Live squashfs / installer UI
