<#
.SYNOPSIS
  Unpack board-results zip and run abi-compare.sh (via bash / WSL / Git Bash).
.DESCRIPTION
  The heavy lifting is Linux readelf/nm; this wrapper only locates bash and forwards args.
  On a pure Windows host without WSL, copy the libs/ folder to a Linux box and run abi-compare.sh there.
.PARAMETER BoardResults
  Path to board-results-*.zip or an already-extracted directory.
.PARAMETER BoardLibs
  Path to a libs/ directory (skips unpack).
.PARAMETER Ours
  Our build directory (default: env PORT/b/acelite-la64 or .\..\..\..\..\b\acelite-la64).
.PARAMETER Out
  Report output directory.
#>
[CmdletBinding()]
param(
    [string]$BoardResults = '',
    [string]$BoardLibs = '',
    [string]$Ours = '',
    [string]$Out = ''
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
No bash/WSL/Git-Bash found. ABI compare needs readelf/nm (Linux).
1. Copy the board-results zip (or its libs\ folder) to a Linux machine / WSL.
2. Run:
     ./abi-compare.sh --board-results board-results-....zip
   or
     ./abi-compare.sh --board-libs /path/to/libs
"@ -ForegroundColor Yellow
    exit 2
}
$argsList = @()
if ($BoardResults) { $argsList += @('--board-results', ($BoardResults -replace '\\','/')) }
if ($BoardLibs)    { $argsList += @('--board-libs', ($BoardLibs -replace '\\','/')) }
if ($Ours)         { $argsList += @('--ours', ($Ours -replace '\\','/')) }
if ($Out)          { $argsList += @('--out', ($Out -replace '\\','/')) }
$script = ($Here + '/abi-compare.sh') -replace '\\','/'
Write-Host "Running: $bash $script $($argsList -join ' ')"
& $bash $script @argsList
exit $LASTEXITCODE
