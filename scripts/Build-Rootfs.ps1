#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Build the Novolis OS rootfs tarball (delegates to build-rootfs.sh on Linux).
#>
[CmdletBinding()]
param(
    [string] $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string] $ProfilePath = '',
    [string] $OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $IsLinux) {
    Write-Error @"
Build-Rootfs.ps1 requires Linux (mmdebstrap) on the host.
On Windows, build via Podman instead:

  pwsh -File $RepoRoot\scripts\Build-PodmanImage.ps1

Or verify allowlists only:

  pwsh -File $RepoRoot\scripts\Verify-PackageBudget.ps1
"@
    exit 1
}

if (-not $ProfilePath) {
    $ProfilePath = Join-Path $RepoRoot 'profiles/default.yaml'
}

$bashBuilder = Join-Path $PSScriptRoot 'build-rootfs.sh'
$bashArgs = @($bashBuilder, $ProfilePath)
if ($OutputPath) { $bashArgs += $OutputPath }
& bash @bashArgs
exit $LASTEXITCODE
