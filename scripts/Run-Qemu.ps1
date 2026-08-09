#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Boot Novolis OS in QEMU (kernel-direct). Uses app already on the qcow (Install-App.ps1).
  Optionally adds virtfs/9p when this QEMU build supports it.
#>
[CmdletBinding()]
param(
    [string] $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string] $Qcow = '',
    [int] $MemoryMb = 2048,
    [int] $Cpus = 2,
    [int] $Width = 1920,
    [int] $Height = 1080,
    [ValidateSet('gtk', 'sdl', 'cocoa', 'default')]
    [string] $Display = 'default',
    [switch] $HeadlessSerial,
    [string] $AppPublishDir = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Find-Qemu {
    $cmd = Get-Command qemu-system-x86_64 -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($c in @(
        'C:\Program Files\qemu\qemu-system-x86_64.exe',
        'C:\Program Files\QEMU\qemu-system-x86_64.exe',
        (Join-Path $env:LOCALAPPDATA 'Programs\qemu\qemu-system-x86_64.exe'),
        (Join-Path $env:USERPROFILE 'scoop\apps\qemu\current\qemu-system-x86_64.exe')
    )) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

if (-not $Qcow) { $Qcow = Join-Path $RepoRoot 'artifacts/novolis-os.qcow2' }
if (-not $AppPublishDir) {
    $candidate = Join-Path $RepoRoot 'artifacts/app-publish'
    if (Test-Path -LiteralPath $candidate) { $AppPublishDir = $candidate }
}

$boot = Join-Path $RepoRoot 'artifacts/boot'
$vmlinuz = Join-Path $boot 'vmlinuz'
$initrd = Join-Path $boot 'initrd.img'
$cmdlineFile = Join-Path $boot 'cmdline.txt'

foreach ($p in @($Qcow, $vmlinuz, $initrd)) {
    if (-not (Test-Path -LiteralPath $p)) {
        throw "Missing $p`n`nBuild first:`n  pwsh -File $RepoRoot\scripts\Build-Appliance.ps1"
    }
}

$qemu = Find-Qemu
if (-not $qemu) {
    throw 'qemu-system-x86_64 not found. Install QEMU under Program Files\qemu or PATH.'
}

$cmdline = 'root=LABEL=novolisos rw rootfstype=ext4 console=tty0'
if (Test-Path -LiteralPath $cmdlineFile) {
    $cmdline = (Get-Content -LiteralPath $cmdlineFile -Raw).Trim()
}
# virtio-gpu default modes are often ~1280-class; ask the guest for a larger KMS mode.
if ($Width -gt 0 -and $Height -gt 0) {
    $videoMode = "video=Virtual-1:${Width}x${Height}@60"
    if ($cmdline -notmatch 'video=Virtual-1:') {
        $cmdline = "$cmdline $videoMode".Trim()
    }
}

$useVirtfs = $false
if ($AppPublishDir) {
    if (-not (Test-Path -LiteralPath $AppPublishDir)) {
        throw "AppPublishDir not found: $AppPublishDir"
    }
    $help = & $qemu -device help 2>&1 | Out-String
    if ($help -match 'virtio-9p') {
        $useVirtfs = $true
        if ($cmdline -notmatch 'novolis\.app=9p') {
            $cmdline += ' novolis.app=9p'
        }
    }
    else {
        Write-Host "Note: this QEMU has no virtfs — booting the app already installed on the qcow (Install-App.ps1)."
    }
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

if ($useVirtfs) {
    $args += @('-virtfs', "local,path=$AppPublishDir,mount_tag=novolisapp,security_model=none,id=novolisapp,multidevs=remap")
    Write-Host "9p share: $AppPublishDir -> novolisapp"
}

if ($HeadlessSerial) {
    $args += @('-nographic', '-serial', 'mon:stdio')
}
else {
    $disp = $Display
    if ($disp -eq 'default') {
        $disp = if ($IsWindows) { 'gtk' } elseif ($IsMacOS) { 'cocoa' } else { 'gtk' }
    }
    $args += @('-display', $disp)
}

Write-Host ("$qemu " + ($args -join ' '))
Write-Host 'Expect cage + /opt/novolis/app (ArtillerySimulator when installed).'
& $qemu @args
exit $LASTEXITCODE
