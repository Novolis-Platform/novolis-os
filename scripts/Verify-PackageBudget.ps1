#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$ResolvedPackagesPath = ''
)
$ErrorActionPreference = 'Stop'
$cs = Join-Path $PSScriptRoot 'Verify-PackageBudget.cs'
$forward = @('--repo', $RepoRoot)
if ($ResolvedPackagesPath) { $forward += @('--resolved', $ResolvedPackagesPath) }
& dotnet run --file $cs -- @forward
exit $LASTEXITCODE
