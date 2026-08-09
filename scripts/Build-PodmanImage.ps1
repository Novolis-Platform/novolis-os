#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Build Novolis OS rootfs inside Podman and import an OCI image (Windows + Linux).
#>
[CmdletBinding()]
param(
    [string] $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string] $Image = 'localhost/novolis-os:latest',
    [string] $BuilderImage = 'docker.io/library/ubuntu:24.04',
    [switch] $SkipRootfsBuild,
    [switch] $SkipSmoke
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Command podman -ErrorAction SilentlyContinue)) {
    throw 'podman not found on PATH. Install Podman Desktop / podman.'
}

& (Join-Path $PSScriptRoot 'Verify-PackageBudget.ps1') -RepoRoot $RepoRoot
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$artifacts = Join-Path $RepoRoot 'artifacts'
$rootfsZst = Join-Path $artifacts 'novolis-os-rootfs.tar.zst'
$rootfsTar = Join-Path $artifacts 'novolis-os-rootfs.tar'
New-Item -ItemType Directory -Force -Path $artifacts | Out-Null

# Podman on Windows needs forward-slash mount paths.
$repoMount = ($RepoRoot -replace '\\', '/')
if ($repoMount -match '^[A-Za-z]:') {
    # C:/... -> /mnt/c/... is NOT used by Podman machine; Podman accepts C:/path
    $repoMount = $repoMount.Substring(0, 1).ToLowerInvariant() + $repoMount.Substring(1)
}

if (-not $SkipRootfsBuild) {
    Write-Host "Building rootfs in privileged $BuilderImage ..."
    $buildScript = @'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  mmdebstrap zstd curl ca-certificates debian-archive-keyring bash xz-utils
cd /src
bash scripts/build-rootfs.sh
'@
    $buildScript = $buildScript -replace "`r`n", "`n"
    $buildScriptPath = Join-Path $artifacts 'podman-build-inner.sh'
    [System.IO.File]::WriteAllText($buildScriptPath, $buildScript + "`n")

    $podmanArgs = @(
        'run', '--rm', '--privileged',
        '-v', "${repoMount}:/src:Z",
        '-w', '/src',
        $BuilderImage,
        'bash', '/src/artifacts/podman-build-inner.sh'
    )
    & podman @podmanArgs
    if ($LASTEXITCODE -ne 0) {
        throw "podman builder failed with exit $LASTEXITCODE"
    }
}

if (-not (Test-Path -LiteralPath $rootfsZst)) {
    throw "Missing rootfs archive: $rootfsZst"
}

Write-Host 'Building OCI image via Containerfile (rootfs + HelloNovolisOs) ...'
& podman build -t $Image -f (Join-Path $RepoRoot 'Containerfile') $RepoRoot
if ($LASTEXITCODE -ne 0) {
    throw "podman build failed with exit $LASTEXITCODE (image must include HelloNovolisOs)."
}

if (-not $SkipSmoke) {
    & (Join-Path $PSScriptRoot 'Run-Podman.ps1') -Image $Image
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Write-Host "Podman image ready: $Image"
exit 0
