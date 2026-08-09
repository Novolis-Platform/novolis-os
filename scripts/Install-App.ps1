#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Install published linux-x64 app + appliance units into novolis-os.qcow2 via WSL root + qemu-nbd.
#>
[CmdletBinding()]
param(
    [string] $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string] $AppPublishDir = '',
    [string] $Qcow = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $AppPublishDir) { $AppPublishDir = Join-Path $RepoRoot 'artifacts/app-publish' }
if (-not $Qcow) { $Qcow = Join-Path $RepoRoot 'artifacts/novolis-os.qcow2' }
if (-not (Test-Path -LiteralPath $AppPublishDir)) { throw "Missing $AppPublishDir" }
if (-not (Test-Path -LiteralPath $Qcow)) { throw "Missing $Qcow" }

$wslQcow = (wsl -e wslpath -a $Qcow).Trim()
$wslPub = (wsl -e wslpath -a $AppPublishDir).Trim()
$wslGui = (wsl -e wslpath -a (Join-Path $RepoRoot 'appliance/systemd/novolis-gui.service')).Trim()
$wslNine = (wsl -e wslpath -a (Join-Path $RepoRoot 'appliance/systemd/novolis-app-9p.service')).Trim()

Write-Host "Installing app + units into qcow2 (WSL root + qemu-nbd)..."

$inner = @"
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
if ! command -v qemu-nbd >/dev/null; then
  apt-get update -qq
  apt-get install -y -qq qemu-utils
fi
modprobe nbd max_part=8
qemu-nbd -d /dev/nbd0 2>/dev/null || true
sleep 1
qemu-nbd -c /dev/nbd0 '$wslQcow'
MNT=`$(mktemp -d)
cleanup() {
  umount "`$MNT" 2>/dev/null || true
  qemu-nbd -d /dev/nbd0 2>/dev/null || true
  rmdir "`$MNT" 2>/dev/null || true
}
trap cleanup EXIT
for i in `$(seq 1 50); do
  if blkid /dev/nbd0 >/dev/null 2>&1; then break; fi
  sleep 0.2
done
mount /dev/nbd0 "`$MNT"
rm -rf "`$MNT/opt/novolis/app"
mkdir -p "`$MNT/opt/novolis/app" "`$MNT/etc/systemd/system/graphical.target.wants"
cp -a '$wslPub'/. "`$MNT/opt/novolis/app/"
rm -f "`$MNT/opt/novolis/app"/*.pdb
cp '$wslGui' "`$MNT/etc/systemd/system/novolis-gui.service"
cp '$wslNine' "`$MNT/etc/systemd/system/novolis-app-9p.service"
ln -sfn /etc/systemd/system/novolis-gui.service "`$MNT/etc/systemd/system/graphical.target.wants/novolis-gui.service"
ln -sfn /etc/systemd/system/novolis-app-9p.service "`$MNT/etc/systemd/system/graphical.target.wants/novolis-app-9p.service"
ls -la "`$MNT/opt/novolis/app" | head
sync
echo OK
"@

$innerPath = Join-Path $RepoRoot 'artifacts/wsl-install-app.sh'
[IO.File]::WriteAllText($innerPath, ($inner -replace "`r`n", "`n") + "`n")
$wslInner = (wsl -e wslpath -a $innerPath).Trim()

# Prefer WSL root (no sudo password) over sudo.
wsl -u root -e bash $wslInner
if ($LASTEXITCODE -ne 0) { throw "WSL install failed: $LASTEXITCODE" }
Write-Host "Done. Boot:"
Write-Host "  pwsh -File $(Join-Path $RepoRoot 'scripts\Run-Qemu.ps1')"
