#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Boot the Novolis OS GUI appliance in QEMU (kernel-direct; virtio-vga).

  Requires: qemu-system-x86_64 on PATH, and artifacts from Build-Appliance.ps1.
#>
[CmdletBinding()]
param(
    [string] $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string] $Qcow = '',
    [int] $MemoryMb = 2048,
    [int] $Cpus = 2,
    [ValidateSet('gtk', 'sdl', 'cocoa', 'default')]
    [string] $Display = 'default',
    [switch] $HeadlessSerial
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $Qcow) {
    $Qcow = Join-Path $RepoRoot 'artifacts/novolis-os.qcow2'
}
$boot = Join-Path $RepoRoot 'artifacts/boot'
$vmlinuz = Join-Path $boot 'vmlinuz'
$initrd = Join-Path $boot 'initrd.img'
$cmdlineFile = Join-Path $boot 'cmdline.txt'

foreach ($p in @($Qcow, $vmlinuz, $initrd)) {
    if (-not (Test-Path -LiteralPath $p)) {
        throw @"
Missing $p

Build the GUI appliance first:

  pwsh -File $RepoRoot\scripts\Build-Appliance.ps1
"@
    }
}

$cmdline = 'root=LABEL=novolisos rw rootfstype=ext4 console=tty0'
if (Test-Path -LiteralPath $cmdlineFile) {
    $cmdline = (Get-Content -LiteralPath $cmdlineFile -Raw).Trim()
}

$qemu = Get-Command qemu-system-x86_64 -ErrorAction SilentlyContinue
if (-not $qemu) {
    throw 'qemu-system-x86_64 not found on PATH. Install QEMU (https://www.qemu.org/).'
}

$args = @(
    '-machine', 'type=q35,accel=whpx:tcg',
    '-m', "$MemoryMb",
    '-smp', "$Cpus",
    '-kernel', $vmlinuz,
    '-initrd', $initrd,
    '-append', $cmdline,
    '-drive', "file=$Qcow,format=qcow2,if=virtio",
    '-device', 'virtio-vga',
    '-device', 'virtio-keyboard-pci',
    '-device', 'virtio-mouse-pci'
)

if ($HeadlessSerial) {
    $args += @('-nographic', '-serial', 'mon:stdio')
}
else {
    # Prefer a windowed display for the Avalonia GUI smoke.
    $disp = $Display
    if ($disp -eq 'default') {
        if ($IsWindows) { $disp = 'gtk' }
        elseif ($IsMacOS) { $disp = 'cocoa' }
        else { $disp = 'gtk' }
    }
    $args += @('-display', $disp)
}

Write-Host ("qemu-system-x86_64 " + ($args -join ' '))
Write-Host 'Expect cage + HelloNovolisOsGui (Avalonia) after systemd reaches graphical.target.'
& qemu-system-x86_64 @args
exit $LASTEXITCODE
