#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Run Novolis OS in Podman (default smoke: .NET 10 runtimes).
#>
[CmdletBinding()]
param(
    [string] $Image = 'localhost/novolis-os:latest',
    [string[]] $Command = @(),
    [switch] $Interactive,
    [string[]] $PodmanArgs = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Command podman -ErrorAction SilentlyContinue)) {
    throw 'podman not found on PATH.'
}

$smoke = $Command.Count -eq 0
if ($smoke) {
    $Command = @('/usr/bin/dotnet', '--list-runtimes')
}

$args = @('run', '--rm')
if ($Interactive) {
    $args += @('-it')
}
$args += $PodmanArgs
$args += @($Image) + $Command

Write-Host ("podman " + ($args -join ' '))
$output = & podman @args 2>&1 | Out-String
$code = $LASTEXITCODE
Write-Host $output.TrimEnd()
if ($code -ne 0) {
    throw "podman run failed with exit $code"
}

if ($smoke) {
    if ($output -notmatch 'Microsoft\.NETCore\.App 10\.') {
        Write-Error "Expected Microsoft.NETCore.App 10.x in container output."
        exit 1
    }
    Write-Host 'OK — Novolis OS runs in Podman with .NET 10 runtime.'
}

exit 0
