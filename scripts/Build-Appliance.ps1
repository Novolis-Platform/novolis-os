#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Build a thin bootable Novolis OS qcow2 (Linux only): appliance rootfs + virt disk.
#>
[CmdletBinding()]
param(
    [string] $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string] $ProfilePath = '',
    [string] $OutputPath = '',
    [int] $DiskSizeGb = 8
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $IsLinux) {
    Write-Error @"
Build-Appliance.ps1 requires Linux.
On Windows, verify allowlists only:

  pwsh -File $RepoRoot\scripts\Verify-PackageBudget.ps1
"@
    exit 1
}

function Get-YamlScalar {
    param(
        [string[]] $Lines,
        [string] $Key
    )
    foreach ($line in $Lines) {
        if ($line -match "^\s*${Key}:\s*(.+)\s*$") {
            return $Matches[1].Trim().Trim('"').Trim("'")
        }
    }
    return $null
}

if (-not $ProfilePath) {
    $ProfilePath = Join-Path $RepoRoot 'profiles/appliance.yaml'
}

$profileLines = Get-Content -LiteralPath $ProfilePath
$rootfsOut = Get-YamlScalar -Lines $profileLines -Key 'rootfs_output'
if (-not $rootfsOut) {
    $rootfsOut = 'artifacts/novolis-os-appliance-rootfs.tar.zst'
}
$rootfsPath = Join-Path $RepoRoot $rootfsOut

if (-not $OutputPath) {
    $fromProfile = Get-YamlScalar -Lines $profileLines -Key 'output'
    if (-not $fromProfile) {
        $fromProfile = 'artifacts/novolis-os.qcow2'
    }
    $OutputPath = Join-Path $RepoRoot $fromProfile
}

foreach ($tool in @('mmdebstrap', 'zstd', 'qemu-img', 'virt-make-fs')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        if ($tool -eq 'virt-make-fs') {
            Write-Warning "virt-make-fs not found; will fall back to raw dd+mkfs if available, else fail."
        }
        elseif ($tool -ne 'virt-make-fs') {
            throw "Required tool not on PATH: $tool"
        }
    }
}

# Build appliance rootfs (includes kernel + cage) using the same path as rootfs builder.
& (Join-Path $PSScriptRoot 'Build-Rootfs.ps1') -RepoRoot $RepoRoot -ProfilePath $ProfilePath -OutputPath $rootfsPath
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$artifactsDir = Join-Path $RepoRoot 'artifacts'
$work = Join-Path $artifactsDir 'appliance-work'
if (Test-Path -LiteralPath $work) {
    Remove-Item -LiteralPath $work -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $work | Out-Null

$extract = Join-Path $work 'root'
New-Item -ItemType Directory -Force -Path $extract | Out-Null
& zstd -d -c $rootfsPath | tar -xf - -C $extract

# Minimal first-boot unit: ensure seatd; document cage usage.
$unitDir = Join-Path $extract 'etc/systemd/system'
New-Item -ItemType Directory -Force -Path $unitDir | Out-Null
$motd = @'
Novolis OS (appliance)
----------------------
Runtime-only image: .NET 10 + Avalonia/Raylib libs, no desktop environment.
Start a Novolis app under cage, for example:
  cage -- /usr/bin/dotnet /opt/app/App.dll
'@
Set-Content -LiteralPath (Join-Path $extract 'etc/motd') -Value $motd -Encoding utf8NoBOM

# Enable seatd if present
$seatdUnit = Join-Path $extract 'lib/systemd/system/seatd.service'
if (Test-Path -LiteralPath $seatdUnit) {
    $wants = Join-Path $extract 'etc/systemd/system/multi-user.target.wants'
    New-Item -ItemType Directory -Force -Path $wants | Out-Null
    $link = Join-Path $wants 'seatd.service'
    if (-not (Test-Path -LiteralPath $link)) {
        & chroot $extract systemctl enable seatd.service 2>$null
        if ($LASTEXITCODE -ne 0) {
            # Fallback symlink when systemctl in chroot is unavailable
            New-Item -ItemType SymbolicLink -Path $link -Target '/lib/systemd/system/seatd.service' -Force | Out-Null
        }
    }
}

$raw = Join-Path $work 'disk.raw'
$sizeBytes = [long]$DiskSizeGb * 1GB

if (Get-Command virt-make-fs -ErrorAction SilentlyContinue) {
    Write-Host "Creating filesystem image with virt-make-fs (${DiskSizeGb}G)..."
    & virt-make-fs -t ext4 -s "${DiskSizeGb}G" --label=novolisos $extract $raw
    if ($LASTEXITCODE -ne 0) {
        throw "virt-make-fs failed with exit $LASTEXITCODE"
    }
}
else {
    throw 'virt-make-fs (guestfs-tools) is required to pack the appliance disk image.'
}

if (Test-Path -LiteralPath $OutputPath) {
    Remove-Item -LiteralPath $OutputPath -Force
}
& qemu-img convert -f raw -O qcow2 $raw $OutputPath
if ($LASTEXITCODE -ne 0) {
    throw "qemu-img convert failed with exit $LASTEXITCODE"
}

Write-Host "Appliance written: $OutputPath"
Write-Host "Note: bootloader/ESP wiring is intentionally thin in v1 — use QEMU with -kernel from the image or extend this script with grub-install for bare metal."
exit 0
