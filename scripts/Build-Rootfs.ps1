#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Build the Novolis OS rootfs tarball with mmdebstrap (Linux only).
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
Build-Rootfs.ps1 requires Linux (mmdebstrap).
On Windows, verify allowlists only:

  pwsh -File $RepoRoot\scripts\Verify-PackageBudget.ps1
"@
    exit 1
}

function Read-PackageList {
    param([string] $Path)
    Get-Content -LiteralPath $Path |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') }
}

function Get-YamlScalar {
    param(
        [string[]] $Lines,
        [string] $Key
    )
    foreach ($line in $Lines) {
        $clean = $line.TrimEnd("`r")
        if ($clean -match "^\s*${Key}:\s*(.+)\s*$") {
            return $Matches[1].Trim().Trim('"').Trim("'")
        }
    }
    return $null
}

function Get-YamlList {
    param(
        [string[]] $Lines,
        [string] $Key
    )
    $items = [System.Collections.Generic.List[string]]::new()
    $inList = $false
    foreach ($line in $Lines) {
        $clean = $line.TrimEnd("`r")
        if ($clean -match "^\s*${Key}:\s*$") {
            $inList = $true
            continue
        }
        if ($inList) {
            if ($clean -match '^\S') {
                break
            }
            if ($clean -match '^\s*-\s+(.+)$') {
                $items.Add($Matches[1].Trim().Trim('"').Trim("'"))
            }
        }
    }
    return @($items)
}

& (Join-Path $PSScriptRoot 'Verify-PackageBudget.ps1') -RepoRoot $RepoRoot
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

if (-not $ProfilePath) {
    $ProfilePath = Join-Path $RepoRoot 'profiles/rootfs.yaml'
}

$profileLines = Get-Content -LiteralPath $ProfilePath
$suite = Get-YamlScalar -Lines $profileLines -Key 'suite'
$variant = Get-YamlScalar -Lines $profileLines -Key 'variant'
if (-not $suite) { $suite = 'trixie' }
if (-not $variant) { $variant = 'minbase' }

$manifestFiles = Get-YamlList -Lines $profileLines -Key 'manifests'
if ($manifestFiles.Count -eq 0) {
    throw "No manifests listed in $ProfilePath"
}

$packages = foreach ($file in $manifestFiles) {
    Read-PackageList -Path (Join-Path $RepoRoot "manifests/$file")
}
$packages = @($packages | Select-Object -Unique)

$aptPackages = @($packages | Where-Object { $_ -ne 'dotnet-runtime-10.0' })
$wantDotnet = $packages -contains 'dotnet-runtime-10.0'

if (-not $OutputPath) {
    $rootfsOutput = Get-YamlScalar -Lines $profileLines -Key 'rootfs_output'
    $output = Get-YamlScalar -Lines $profileLines -Key 'output'
    $relative = $null
    if ($rootfsOutput) {
        $relative = $rootfsOutput
    }
    elseif ($output -and $output -like '*.tar.zst') {
        $relative = $output
    }
    else {
        $relative = 'artifacts/novolis-os-rootfs.tar.zst'
    }
    $OutputPath = Join-Path $RepoRoot $relative
}

$artifactsDir = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force -Path $artifactsDir | Out-Null

foreach ($tool in @('mmdebstrap', 'zstd', 'tar')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Required tool not on PATH: $tool"
    }
}

$work = Join-Path $artifactsDir 'rootfs-work'
if (Test-Path -LiteralPath $work) {
    Remove-Item -LiteralPath $work -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $work | Out-Null

$hookDir = Join-Path $work 'hooks'
New-Item -ItemType Directory -Force -Path $hookDir | Out-Null
$setupMs = Join-Path $hookDir 'setup-microsoft.sh'

if ($wantDotnet) {
    $msScript = @'
#!/bin/sh
set -eu
root="$1"
export DEBIAN_FRONTEND=noninteractive
chroot "$root" apt-get update -qq
chroot "$root" apt-get install -y -qq --no-install-recommends ca-certificates curl
curl -fsSL https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb -o "$root/tmp/packages-microsoft-prod.deb"
chroot "$root" dpkg -i /tmp/packages-microsoft-prod.deb
rm -f "$root/tmp/packages-microsoft-prod.deb"
chroot "$root" apt-get update -qq
chroot "$root" apt-get install -y -qq --no-install-recommends dotnet-runtime-10.0
chroot "$root" apt-get purge -y -qq curl || true
chroot "$root" apt-get autoremove -y -qq
chroot "$root" apt-get clean
rm -rf "$root/var/lib/apt/lists/"*
'@
}
else {
    $msScript = "#!/bin/sh`nexit 0`n"
}

Set-Content -LiteralPath $setupMs -Value $msScript -Encoding utf8NoBOM
& chmod +x $setupMs

$tarTmp = Join-Path $work 'rootfs.tar'
Write-Host "mmdebstrap suite=$suite variant=$variant packages=$($aptPackages.Count) (+dotnet hook=$wantDotnet)"

# Invoke via bash so aptopt quoting is not re-parsed by PowerShell.
function ConvertTo-BashSingleQuoted {
    param([string] $Value)
    return "'" + ($Value -replace "'", "'\''") + "'"
}

$keyring = '/usr/share/keyrings/debian-archive-keyring.gpg'
if (-not (Test-Path -LiteralPath $keyring)) {
    throw "Missing $keyring — install debian-archive-keyring on the build host."
}

$bashLines = [System.Collections.Generic.List[string]]::new()
[void]$bashLines.Add('#!/bin/bash')
[void]$bashLines.Add('set -euo pipefail')
$aptOpt = 'Apt::Install-Recommends "false"'
$cmdParts = [System.Collections.Generic.List[string]]::new()
# Root mode + Debian keyring: unshare on Ubuntu hosts often lacks Debian archive keys.
$uid = (& bash -lc 'id -u').ToString().Trim()
$useSudo = $uid -ne '0'
if ($useSudo) {
    [void]$cmdParts.Add('sudo')
}
[void]$cmdParts.Add('mmdebstrap')
[void]$cmdParts.Add("--variant=$(ConvertTo-BashSingleQuoted $variant)")
[void]$cmdParts.Add('--mode=root')
[void]$cmdParts.Add("--keyring=$(ConvertTo-BashSingleQuoted $keyring)")
[void]$cmdParts.Add("--aptopt=$(ConvertTo-BashSingleQuoted $aptOpt)")
foreach ($pkg in $aptPackages) {
    [void]$cmdParts.Add("--include=$(ConvertTo-BashSingleQuoted $pkg)")
}
if ($wantDotnet) {
    [void]$cmdParts.Add("--customize-hook=$(ConvertTo-BashSingleQuoted $setupMs)")
}
[void]$cmdParts.Add((ConvertTo-BashSingleQuoted $suite))
[void]$cmdParts.Add((ConvertTo-BashSingleQuoted $tarTmp))
[void]$bashLines.Add(($cmdParts -join ' '))

$runner = Join-Path $work 'run-mmdebstrap.sh'
# UTF-8 no BOM; LF newlines for bash
[System.IO.File]::WriteAllText($runner, (($bashLines -join "`n") + "`n"))
& chmod +x $runner
Write-Host "Running $runner"
& bash $runner
if ($LASTEXITCODE -ne 0) {
    throw "mmdebstrap failed with exit $LASTEXITCODE"
}

if ($useSudo) {
    & sudo chown -R "${uid}:${uid}" $work
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to chown rootfs work directory after sudo mmdebstrap.'
    }
}

$extract = Join-Path $work 'extract'
New-Item -ItemType Directory -Force -Path $extract | Out-Null
& tar -xf $tarTmp -C $extract
$status = Join-Path $extract 'var/lib/dpkg/status'
$resolvedPath = Join-Path $artifactsDir 'resolved-packages.txt'
if (Test-Path -LiteralPath $status) {
    $names = Select-String -Path $status -Pattern '^Package:\s+(.+)$' | ForEach-Object { $_.Matches.Groups[1].Value } | Sort-Object -Unique
    $names | Set-Content -LiteralPath $resolvedPath -Encoding utf8
    Write-Host "Wrote $($names.Count) resolved packages -> $resolvedPath"
    & (Join-Path $PSScriptRoot 'Verify-PackageBudget.ps1') -RepoRoot $RepoRoot -ResolvedPackagesPath $resolvedPath
    if ($LASTEXITCODE -ne 0) {
        throw 'Resolved package set failed budget/exclude check.'
    }
}

if (Test-Path -LiteralPath $OutputPath) {
    Remove-Item -LiteralPath $OutputPath -Force
}
& zstd -T0 -19 -o $OutputPath $tarTmp
if ($LASTEXITCODE -ne 0) {
    throw "zstd failed with exit $LASTEXITCODE"
}

Write-Host "Rootfs written: $OutputPath"
exit 0
