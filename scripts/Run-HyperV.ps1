#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Attach the Novolis OS UEFI hybrid disk to a Hyper-V Generation 2 VM and start it.

  Uses the GPT ESP+root image (not the old single-partition qcow-derived vhdx).
  Secure Boot must stay off (unsigned GRUB).
#>
[CmdletBinding()]
param(
    [string] $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string] $Image = '',
    [string] $Vhdx = '',
    [string] $VmName = 'NovolisOS',
    [int] $MemoryMb = 4096,
    [int] $Cpus = 2,
    [switch] $NoStart,
    [switch] $ForceRecreate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Find-QemuImg {
    $cmd = Get-Command qemu-img -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($c in @(
        'C:\Program Files\qemu\qemu-img.exe',
        'C:\Program Files\QEMU\qemu-img.exe'
    )) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}

if (-not (Get-Command New-VM -ErrorAction SilentlyContinue)) {
    throw 'Hyper-V PowerShell module not available. Enable Hyper-V and reopen an elevated PowerShell.'
}

if (-not (Test-IsAdministrator)) {
    throw @"
Hyper-V VM create/start needs an elevated PowerShell.

  Start-Process pwsh -Verb RunAs -ArgumentList '-NoProfile -File `"$PSCommandPath`"'
"@
}

if (-not $Image) {
    $Image = Join-Path $RepoRoot 'artifacts/novolis-os-uefi.img'
    if (-not (Test-Path -LiteralPath $Image)) {
        $Image = Join-Path $RepoRoot 'artifacts/novolis-os.iso'
    }
}
if (-not (Test-Path -LiteralPath $Image)) {
    throw "Missing UEFI hybrid image.`nBuild first:`n  pwsh -File $RepoRoot\scripts\Build-Appliance.ps1"
}

if (-not $Vhdx) {
    $Vhdx = Join-Path $RepoRoot 'artifacts/novolis-os-uefi.vhdx'
}

$qemuImg = Find-QemuImg
if (-not $qemuImg) {
    throw 'qemu-img not found (needed to convert raw GPT hybrid → VHDX).'
}

$needConvert = $ForceRecreate -or -not (Test-Path -LiteralPath $Vhdx)
if (-not $needConvert) {
    $imgTime = (Get-Item -LiteralPath $Image).LastWriteTimeUtc
    $vhdxTime = (Get-Item -LiteralPath $Vhdx).LastWriteTimeUtc
    if ($imgTime -gt $vhdxTime) { $needConvert = $true }
}

if ($needConvert) {
    Write-Host "Converting raw GPT hybrid → VHDX:`n  $Image`n  → $Vhdx"
    if (Test-Path -LiteralPath $Vhdx) {
        # Detach if a VM is using it
        Get-VMHardDiskDrive -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -eq $Vhdx } |
            ForEach-Object {
                Write-Host "Detaching $Vhdx from VM $($_.VMName)..."
                Remove-VMHardDiskDrive -VMName $_.VMName -ControllerType $_.ControllerType `
                    -ControllerNumber $_.ControllerNumber -ControllerLocation $_.ControllerLocation
            }
        Remove-Item -LiteralPath $Vhdx -Force
    }
    & $qemuImg convert -p -f raw -O vhdx $Image $Vhdx
    if ($LASTEXITCODE -ne 0) {
        throw "qemu-img convert failed with exit $LASTEXITCODE"
    }
}

# Hyper-V rejects sparse / NTFS-compressed VHDs (0xC03A001A).
function Repair-HyperVDiskAttributes([string] $Path) {
    Write-Host "Clearing sparse/compressed attributes on $Path"
    & fsutil.exe sparse setFlag $Path 0 | Out-Null
    & compact.exe /U $Path | Out-Null
    $item = Get-Item -LiteralPath $Path -Force
    $item.Attributes = $item.Attributes -band (-bnot [IO.FileAttributes]::Compressed) -band (-bnot [IO.FileAttributes]::SparseFile)
}

Repair-HyperVDiskAttributes -Path $Vhdx

$existing = Get-VM -Name $VmName -ErrorAction SilentlyContinue
if ($existing -and $ForceRecreate) {
    Write-Host "Removing existing VM '$VmName'..."
    if ($existing.State -ne 'Off') {
        Stop-VM -Name $VmName -Force -TurnOff
    }
    Remove-VM -Name $VmName -Force
    $existing = $null
}

if (-not $existing) {
    Write-Host "Creating Generation 2 VM '$VmName'..."
    $null = New-VM -Name $VmName -Generation 2 -MemoryStartupBytes ([uint64]$MemoryMb * 1MB) `
        -VHDPath $Vhdx -SwitchName (Get-VMSwitch | Select-Object -First 1 -ExpandProperty Name)
    Set-VMProcessor -VMName $VmName -Count $Cpus
    # Unsigned GRUB — Secure Boot must be off
    Set-VMFirmware -VMName $VmName -EnableSecureBoot Off
    # Prefer booting from the attached hard disk
    $hdd = Get-VMHardDiskDrive -VMName $VmName | Select-Object -First 1
    Set-VMFirmware -VMName $VmName -FirstBootDevice $hdd
}
else {
    Write-Host "VM '$VmName' already exists — ensuring Secure Boot off and disk attached."
    Set-VMFirmware -VMName $VmName -EnableSecureBoot Off
    $attached = Get-VMHardDiskDrive -VMName $VmName | Where-Object { $_.Path -eq $Vhdx }
    if (-not $attached) {
        # Replace boot disk if a different VHDX is attached
        Get-VMHardDiskDrive -VMName $VmName | ForEach-Object {
            Remove-VMHardDiskDrive -VMName $VmName -ControllerType $_.ControllerType `
                -ControllerNumber $_.ControllerNumber -ControllerLocation $_.ControllerLocation
        }
        Add-VMHardDiskDrive -VMName $VmName -Path $Vhdx
        $hdd = Get-VMHardDiskDrive -VMName $VmName | Select-Object -First 1
        Set-VMFirmware -VMName $VmName -FirstBootDevice $hdd
    }
    Set-VMMemory -VMName $VmName -StartupBytes ([uint64]$MemoryMb * 1MB)
    Set-VMProcessor -VMName $VmName -Count $Cpus
}

$vm = Get-VM -Name $VmName
Write-Host "VM: $($vm.Name)  Gen=$($vm.Generation)  State=$($vm.State)"
Write-Host "Disk: $Vhdx"
Write-Host "Secure Boot: $((Get-VMFirmware -VMName $VmName).SecureBoot)"

if (-not $NoStart) {
    if ($vm.State -eq 'Off') {
        Start-VM -Name $VmName
        Write-Host "Started '$VmName'."
    }
    else {
        Write-Host "VM already $($vm.State)."
    }
    # Open VM Connect if available
    $vmconnect = Join-Path $env:SystemRoot 'System32\vmconnect.exe'
    if (Test-Path -LiteralPath $vmconnect) {
        Start-Process -FilePath $vmconnect -ArgumentList @('localhost', $VmName)
    }
    else {
        Write-Host "Open Hyper-V Manager → connect to '$VmName'."
    }
}

Write-Host "Expect UEFI → GRUB → systemd → cage → /opt/novolis/app"
exit 0
