<#
.SYNOPSIS
  Forward to pack-debug-libs.sh via bash/WSL/Git Bash.
.PARAMETER BoardResults
  board-results zip or extracted dir.
.PARAMETER BoardLibs
  libs/ directory.
.PARAMETER Ours
  Our build dir (default b/acelite-la64).
.PARAMETER Report
  Existing abi-report.json (or its directory).
.PARAMETER Out
  Output directory for the zip.
.PARAMETER AfterRelink
  Allow packing when verdict is CONDITIONAL (BOARD_NEEDED).
#>
[CmdletBinding()]
param(
    [string]$BoardResults = '',
    [string]$BoardLibs = '',
    [string]$Ours = '',
    [string]$Report = '',
    [string]$Out = '',
    [switch]$AfterRelink
)
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
function Find-Bash {
    foreach ($c in @(
        'bash',
        "$env:WINDIR\System32\bash.exe",
        'C:\Program Files\Git\bin\bash.exe',
        'C:\Program Files (x86)\Git\bin\bash.exe'
    )) {
        $cmd = Get-Command $c -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}
$bash = Find-Bash
if (-not $bash) {
    Write-Host @"
No bash/WSL/Git-Bash found. pack-debug-libs needs the Linux abi-compare toolchain.
Copy board libs + this folder to a Linux host and run:
  ./pack-debug-libs.sh --board-libs /path/to/libs
"@ -ForegroundColor Yellow
    exit 2
}
$argsList = @()
if ($BoardResults) { $argsList += @('--board-results', ($BoardResults -replace '\\','/')) }
if ($BoardLibs)    { $argsList += @('--board-libs', ($BoardLibs -replace '\\','/')) }
if ($Ours)         { $argsList += @('--ours', ($Ours -replace '\\','/')) }
if ($Report)       { $argsList += @('--report', ($Report -replace '\\','/')) }
if ($Out)          { $argsList += @('--out', ($Out -replace '\\','/')) }
if ($AfterRelink)  { $argsList += '--after-relink' }
$script = ($Here + '/pack-debug-libs.sh') -replace '\\','/'
Write-Host "Running: $bash $script $($argsList -join ' ')"
& $bash $script @argsList
exit $LASTEXITCODE
