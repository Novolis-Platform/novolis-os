#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Boot the Novolis OS UEFI hybrid ISO/img in QEMU with OVMF (no -kernel).
#>
[CmdletBinding()]
param(
    [string] $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string] $Iso = '',
    [int] $MemoryMb = 2048,
    [int] $Cpus = 2,
    [ValidateSet('gtk', 'sdl', 'cocoa', 'default')]
    [string] $Display = 'default',
    [switch] $HeadlessSerial,
    [string] $OvmfCode = '',
    [string] $OvmfVars = ''
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

function Find-OvmfCode {
    param([string] $QemuPath)
    $dirs = [System.Collections.Generic.List[string]]::new()
    if ($QemuPath) {
        $qemuDir = Split-Path -Parent $QemuPath
        $dirs.Add((Join-Path $qemuDir 'share'))
        $dirs.Add((Join-Path $qemuDir 'share\edk2'))
        $dirs.Add((Join-Path $qemuDir 'share\qemu'))
        $parent = Split-Path -Parent $qemuDir
        if ($parent) {
            $dirs.Add((Join-Path $parent 'share\edk2'))
            $dirs.Add((Join-Path $parent 'share\qemu'))
            $dirs.Add((Join-Path $parent 'share'))
        }
    }
    $dirs.Add('C:\Program Files\qemu\share')
    $dirs.Add('C:\Program Files\qemu\share\edk2')
    $dirs.Add('/usr/share/OVMF')
    $dirs.Add('/usr/share/edk2/ovmf')
    $dirs.Add('/usr/share/qemu')

    $names = @(
        'edk2-x86_64-code.fd',
        'OVMF_CODE.fd',
        'OVMF_CODE_4M.fd',
        'OVMF.fd'
    )
    foreach ($d in $dirs) {
        if (-not $d -or -not (Test-Path -LiteralPath $d)) { continue }
        foreach ($n in $names) {
            $p = Join-Path $d $n
            if (Test-Path -LiteralPath $p) { return $p }
        }
        $hit = Get-ChildItem -LiteralPath $d -Recurse -Filter 'OVMF_CODE*.fd' -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($hit) { return $hit.FullName }
        $hit2 = Get-ChildItem -LiteralPath $d -Recurse -Filter 'edk2-x86_64-code.fd' -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($hit2) { return $hit2.FullName }
    }
    return $null
}

function Find-OvmfVarsTemplate {
    param([string] $CodePath)
    if (-not $CodePath) { return $null }
    $dir = Split-Path -Parent $CodePath
    foreach ($n in @('edk2-i386-vars.fd', 'OVMF_VARS.fd', 'OVMF_VARS_4M.fd')) {
        $p = Join-Path $dir $n
        if (Test-Path -LiteralPath $p) { return $p }
    }
    $hit = Get-ChildItem -LiteralPath $dir -Filter 'OVMF_VARS*.fd' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($hit) { return $hit.FullName }
    $hit2 = Get-ChildItem -LiteralPath $dir -Filter 'edk2-*-vars.fd' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($hit2) { return $hit2.FullName }
    return $null
}

if (-not $Iso) {
    $Iso = Join-Path $RepoRoot 'artifacts/novolis-os.iso'
    if (-not (Test-Path -LiteralPath $Iso)) {
        $Iso = Join-Path $RepoRoot 'artifacts/novolis-os-uefi.img'
    }
}

if (-not (Test-Path -LiteralPath $Iso)) {
    throw "Missing UEFI media at $Iso`n`nBuild first:`n  pwsh -File $RepoRoot\scripts\Build-Appliance.ps1"
}

$qemu = Find-Qemu
if (-not $qemu) {
    throw 'qemu-system-x86_64 not found. Install QEMU under Program Files\qemu or PATH.'
}

if (-not $OvmfCode) {
    $OvmfCode = Find-OvmfCode -QemuPath $qemu
}
if (-not $OvmfCode -or -not (Test-Path -LiteralPath $OvmfCode)) {
    throw @"
OVMF firmware not found (UEFI).
Install QEMU with edk2/OVMF share files, or pass -OvmfCode path.

  pwsh -File $RepoRoot\scripts\Run-Iso.ps1 -OvmfCode 'C:\path\to\OVMF_CODE.fd'
"@
}

$varsTemplate = $OvmfVars
if (-not $varsTemplate) {
    $varsTemplate = Find-OvmfVarsTemplate -CodePath $OvmfCode
}

$pflashArgs = [System.Collections.Generic.List[string]]::new()
if ($varsTemplate -and (Test-Path -LiteralPath $varsTemplate)) {
    $varsCopy = Join-Path $RepoRoot 'artifacts/ovmf-vars.fd'
    Copy-Item -LiteralPath $varsTemplate -Destination $varsCopy -Force
    $pflashArgs.AddRange([string[]]@(
        '-drive', "if=pflash,format=raw,readonly=on,file=$OvmfCode",
        '-drive', "if=pflash,format=raw,file=$varsCopy"
    ))
}
else {
    # Single-blob OVMF.fd works read-only for smoke boots.
    $pflashArgs.AddRange([string[]]@(
        '-drive', "if=pflash,format=raw,readonly=on,file=$OvmfCode"
    ))
}

$args = [System.Collections.Generic.List[string]]::new()
$args.AddRange([string[]]@(
    '-machine', 'type=q35,accel=whpx:tcg',
    '-m', "$MemoryMb",
    '-smp', "$Cpus"
))
$args.AddRange($pflashArgs)
$args.AddRange([string[]]@(
    '-drive', "file=$Iso,format=raw,if=virtio",
    '-device', 'virtio-vga',
    '-device', 'virtio-keyboard-pci',
    '-device', 'virtio-mouse-pci'
))

if ($HeadlessSerial) {
    $args.AddRange([string[]]@('-nographic', '-serial', 'mon:stdio'))
}
else {
    $disp = $Display
    if ($disp -eq 'default') {
        $disp = if ($IsWindows) { 'gtk' } elseif ($IsMacOS) { 'cocoa' } else { 'gtk' }
    }
    $args.AddRange([string[]]@('-display', $disp))
}

Write-Host ("$qemu " + ($args -join ' '))
Write-Host 'Expect OVMF → GRUB → systemd → cage → /opt/novolis/app'
& $qemu @args
exit $LASTEXITCODE
