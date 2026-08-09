#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Build the Novolis OS GUI appliance (qcow2 + kernel/initrd for QEMU).

  On Windows, builds inside a privileged Podman container (Linux tools + .NET SDK).
#>
[CmdletBinding()]
param(
    [string] $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string] $ProfilePath = '',
    [int] $DiskSizeGb = 8,
    [string] $BuilderImage = 'docker.io/library/ubuntu:24.04'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ProfilePath) {
    $ProfilePath = Join-Path $RepoRoot 'profiles/appliance.yaml'
}

& (Join-Path $PSScriptRoot 'Verify-PackageBudget.ps1') -RepoRoot $RepoRoot
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

function ConvertTo-PodmanMount([string] $Path) {
    $m = ($Path -replace '\\', '/')
    if ($m -match '^[A-Za-z]:') {
        $m = $m.Substring(0, 1).ToLowerInvariant() + $m.Substring(1)
    }
    return $m
}

if ($IsLinux) {
    $env:DISK_GB = "$DiskSizeGb"
    & bash (Join-Path $PSScriptRoot 'build-appliance.sh') $ProfilePath
    exit $LASTEXITCODE
}

if (-not (Get-Command podman -ErrorAction SilentlyContinue)) {
    throw @"
Appliance builds need Linux tools (mmdebstrap, virt-make-fs) or Podman Desktop.
Install Podman, then re-run:

  pwsh -File $RepoRoot\scripts\Build-Appliance.ps1
"@
}

$repoMount = ConvertTo-PodmanMount $RepoRoot
$artifacts = Join-Path $RepoRoot 'artifacts'
New-Item -ItemType Directory -Force -Path $artifacts | Out-Null

$inner = @'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export DISK_GB="${DISK_GB:-8}"
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  mmdebstrap zstd curl ca-certificates debian-archive-keyring bash xz-utils \
  qemu-utils e2fsprogs rsync mount libicu74
# .NET SDK 10 for publishing Avalonia + console smokes
curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
bash /tmp/dotnet-install.sh --channel 10.0 --install-dir /usr/share/dotnet
ln -sfn /usr/share/dotnet/dotnet /usr/bin/dotnet
export DOTNET_ROOT=/usr/share/dotnet
export PATH="/usr/share/dotnet:$PATH"
export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=0
cd /src
chmod +x scripts/build-appliance.sh scripts/build-rootfs.sh scripts/verify-package-budget.sh
bash scripts/build-appliance.sh /src/profiles/appliance.yaml
'@
$inner = $inner -replace "`r`n", "`n"
$innerPath = Join-Path $artifacts 'podman-appliance-inner.sh'
[System.IO.File]::WriteAllText($innerPath, $inner + "`n")

Write-Host "Building GUI appliance in privileged $BuilderImage (this takes a while)..."
$skipRootfs = if (Test-Path (Join-Path $RepoRoot 'artifacts/novolis-os-appliance-rootfs.tar.zst')) { '1' } else { '0' }
& podman run --rm --privileged `
    -e "DISK_GB=$DiskSizeGb" `
    -e "SKIP_ROOTFS=$skipRootfs" `
    -v "${repoMount}:/src:Z" `
    -w /src `
    $BuilderImage `
    bash /src/artifacts/podman-appliance-inner.sh
if ($LASTEXITCODE -ne 0) {
    throw "Appliance Podman build failed with exit $LASTEXITCODE"
}

Write-Host "Appliance ready:"
Write-Host "  $(Join-Path $RepoRoot 'artifacts\novolis-os.qcow2')"
Write-Host "  $(Join-Path $RepoRoot 'artifacts\boot\vmlinuz')"
Write-Host "Run: pwsh -File $(Join-Path $RepoRoot 'scripts\Run-Qemu.ps1')"
exit 0
