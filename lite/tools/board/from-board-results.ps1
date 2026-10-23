<#
.SYNOPSIS
  Run from-board-results.sh: unpack → abi-compare → optional BOARD_NEEDED relink → pack.
.PARAMETER BoardResults
  Path to board-results-*.zip (required).
.PARAMETER Ours
  Our debug libs dir (default b/acelite-la64).
.PARAMETER Work
  Work directory for intermediates (kept on failure).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BoardResults,
    [string]$Ours = '',
    [string]$Work = ''
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
No bash/WSL/Git-Bash found. from-board-results needs Linux readelf/nm + the .sh pipeline.
Copy the board-results zip to a Linux host and run:
  ./from-board-results.sh board-results-….zip
"@ -ForegroundColor Yellow
    exit 2
}
$argsList = @(($BoardResults -replace '\\','/'))
if ($Ours) { $argsList += @('--ours', ($Ours -replace '\\','/')) }
if ($Work) { $argsList += @('--work', ($Work -replace '\\','/')) }
$script = ($Here + '/from-board-results.sh') -replace '\\','/'
Write-Host "Running: $bash $script $($argsList -join ' ')"
& $bash $script @argsList
exit $LASTEXITCODE
