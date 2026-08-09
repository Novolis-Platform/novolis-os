#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Run Novolis OS in Podman. Default: launch HelloNovolisOs (the image entrypoint app).
#>
[CmdletBinding()]
param(
    [string] $Image = 'localhost/novolis-os:latest',
    # When set, replaces the default smoke (--once). Empty = smoke once and exit.
    [string[]] $Command = @(),
    [switch] $Interactive,
    [switch] $Stay,
    [string[]] $PodmanArgs = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Command podman -ErrorAction SilentlyContinue)) {
    throw 'podman not found on PATH.'
}

$smoke = -not $Stay -and $Command.Count -eq 0
$args = @('run', '--rm')
if ($Interactive -or $Stay) {
    $args += @('-it')
}
$args += $PodmanArgs
$args += @($Image)

if ($smoke) {
    $args += @('--once')
}
elseif ($Command.Count -gt 0) {
    # Override entrypoint for shell / custom commands
    $args = @('run', '--rm')
    if ($Interactive) { $args += @('-it') }
    $args += $PodmanArgs
    $args += @('--entrypoint', $Command[0], $Image)
    if ($Command.Count -gt 1) {
        $args += $Command[1..($Command.Count - 1)]
    }
}

Write-Host ("podman " + ($args -join ' '))
$output = & podman @args 2>&1 | Out-String
$code = $LASTEXITCODE
Write-Host $output.TrimEnd()
if ($code -ne 0) {
    throw "podman run failed with exit $code"
}

if ($smoke) {
    if ($output -notmatch 'app=HelloNovolisOs') {
        Write-Error "Expected HelloNovolisOs app banner in container output."
        exit 1
    }
    if ($output -notmatch 'status=running') {
        Write-Error "Expected status=running from HelloNovolisOs."
        exit 1
    }
    if ($output -notmatch '\.NET 10|\.NETCore\.App|net10|10\.\d') {
        # FrameworkDescription usually looks like ".NET 10.0.x"
        Write-Warning "Could not confirm .NET 10 in FrameworkDescription; continuing if app ran."
    }
    Write-Host 'OK — Novolis OS launched HelloNovolisOs in Podman.'
}

exit 0
