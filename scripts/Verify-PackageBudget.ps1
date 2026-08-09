#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Enforce Novolis OS package allowlists and budgets (single profile).
#>
[CmdletBinding()]
param(
    [string] $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string] $ResolvedPackagesPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-PackageList {
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Missing package list: $Path"
    }
    Get-Content -LiteralPath $Path |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') }
}

function Test-ExcludeMatch {
    param(
        [string] $Name,
        [string[]] $Patterns
    )
    foreach ($pattern in $Patterns) {
        if ($Name -like $pattern) {
            return $true
        }
    }
    return $false
}

$manifestDir = Join-Path $RepoRoot 'manifests'
$manifestFiles = @('base.txt', 'dotnet.txt', 'ui-graphics.txt', 'audio-alsa.txt', 'appliance.txt')
$excludePath = Join-Path $manifestDir 'excludes.txt'

$excludes = @(Read-PackageList -Path $excludePath)
$allExplicit = @(
    foreach ($file in $manifestFiles) {
        Read-PackageList -Path (Join-Path $manifestDir $file)
    }
) | Select-Object -Unique
$allExplicit = @($allExplicit)

$allCount = $allExplicit.Count
$maxExplicit = 80
$maxResolved = 280

$failures = [System.Collections.Generic.List[string]]::new()

if ($allCount -gt $maxExplicit) {
    $failures.Add("Explicit packages: $allCount > budget $maxExplicit")
}

foreach ($pkg in $allExplicit) {
    if (Test-ExcludeMatch -Name $pkg -Patterns $excludes) {
        $failures.Add("Allowlist package '$pkg' matches hard exclude")
    }
}

$seen = @{}
foreach ($file in $manifestFiles) {
    foreach ($pkg in (Read-PackageList -Path (Join-Path $manifestDir $file))) {
        if ($seen.ContainsKey($pkg)) {
            Write-Warning "Package '$pkg' listed in both '$($seen[$pkg])' and '$file' (allowed but noisy)."
        }
        else {
            $seen[$pkg] = $file
        }
    }
}

if (-not $ResolvedPackagesPath) {
    $candidate = Join-Path $RepoRoot 'artifacts/resolved-packages.txt'
    if (Test-Path -LiteralPath $candidate) {
        $ResolvedPackagesPath = $candidate
    }
}

if ($ResolvedPackagesPath -and (Test-Path -LiteralPath $ResolvedPackagesPath)) {
    $resolved = @(Read-PackageList -Path $ResolvedPackagesPath)
    if ($resolved.Count -gt $maxResolved) {
        $failures.Add("Resolved packages: $($resolved.Count) > budget $maxResolved")
    }
    foreach ($pkg in $resolved) {
        if (Test-ExcludeMatch -Name $pkg -Patterns $excludes) {
            $failures.Add("Resolved package '$pkg' matches hard exclude")
        }
    }
}

Write-Host "Novolis OS package budget (single profile)"
Write-Host "  explicit : $allCount / $maxExplicit"
if ($ResolvedPackagesPath -and (Test-Path -LiteralPath $ResolvedPackagesPath)) {
    $resolvedCount = @(Read-PackageList -Path $ResolvedPackagesPath).Count
    Write-Host "  resolved : $resolvedCount / $maxResolved"
}
else {
    Write-Host "  resolved : (no artifacts/resolved-packages.txt yet)"
}

if ($failures.Count -gt 0) {
    Write-Error ("Package budget failed:`n  - " + ($failures -join "`n  - "))
    exit 1
}

Write-Host "OK — allowlists within budget and clear of hard excludes."
exit 0
