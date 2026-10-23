<#
.SYNOPSIS
  One-click hdcd board check for the OpenHarmony small system (LoongArch64) - hdcd lite handoff package.

.DESCRIPTION
  Connects to a board that already runs hdcd (see README "Step 0" for the manual first copy), then runs
  every BOARD-CHECKLIST TCP check, U1-U8, 6b, 6c, a ~20 MB file round trip, and collects ACE/jerry libs
  and system info. Every check is written to its own .txt (command header + output). A single failure never
  aborts the run. Results go to Summary.txt and board-results-<timestamp>.zip.

  The script is read-only towards the system: it never replaces or modifies system libraries and never
  remounts anything. It only writes under -RemoteDir (default /tmp/ohjs) and, with -Upgrade, the hdcd
  directory it picks (/data/hdcd, /data/local/tmp/hdcd or /tmp/hdcd).

  Compatible with Windows PowerShell 5.1 and PowerShell 7.

.PARAMETER Target
  Board IP (or ip:port). Prompted for when omitted.
.PARAMETER Port
  hdcd TCP port on the board. Default 8710.
.PARAMETER Hdc
  Path to hdc.exe. Default: hdc / hdc.exe found on PATH. Must be 6.1-LTS Ver 3.2.0c (see host/README.md).
.PARAMETER ServerPort
  Host hdc server port. Default 8710. (This only conflicts with hdcd when hdcd runs on the same host,
  e.g. the qemu test environment; then use 8711.)
.PARAMETER Upgrade
  If an old hdcd is reachable: send the package hdcd + hdcd.para to a writable dir, restart hdcd from there
  and reconnect.
.PARAMETER PackageDir
  Package root containing hdcd.stripped and etc/hdcd.para. Default: the script directory.
.PARAMETER OutDir
  Where board-results-<timestamp> and the zip are created. Default: current directory.
.PARAMETER RemoteDir
  Writable scratch dir on the board. Default /tmp/ohjs.
.PARAMETER LibSearchRoots
  Board directories searched for libace_*.so / libjerry*.so. Default "/".
.PARAMETER StartCmd
  Board command used by -Upgrade to start the new hdcd; __DIR__ is replaced with the hdcd dir.
.PARAMETER BigFileMB
  Size of the round-trip test file. Default 20.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\board-check.ps1 -Target 192.168.1.50
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\board-check.ps1 -Target 192.168.1.50 -Upgrade
#>
[CmdletBinding()]
param(
    [string]$Target = '',
    [int]$Port = 8710,
    [string]$Hdc = '',
    [int]$ServerPort = 8710,
    [switch]$Upgrade,
    [string]$PackageDir = '',
    [string]$OutDir = '',
    [string]$RemoteDir = '/tmp/ohjs',
    [string[]]$LibSearchRoots = @('/'),
    [string]$StartCmd = 'HDC_OSAL_DEFAULT_PARA=__DIR__/hdcd.para HDC_OSAL_PERSIST_PARA=__DIR__/persist.para ./hdcd -t -l4',
    [int]$BigFileMB = 20
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

# ---------------------------------------------------------------- setup
if (-not $PackageDir) { $PackageDir = $PSScriptRoot }
if (-not $PackageDir) { $PackageDir = (Get-Location).Path }
if (-not $OutDir) { $OutDir = (Get-Location).Path }

if (-not $Hdc) {
    $cmd = Get-Command 'hdc.exe', 'hdc' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { $Hdc = $cmd.Source }
}
if (-not $Hdc -or -not (Test-Path -LiteralPath $Hdc)) {
    Write-Host "ERROR: hdc not found. Pass -Hdc C:\path\to\hdc.exe or add it to PATH." -ForegroundColor Red
    exit 2
}
if (-not $Target) { $Target = Read-Host 'Board IP address (e.g. 192.168.1.50)' }
$Target = $Target.Trim()
if (-not $Target) { Write-Host 'ERROR: no target given.' -ForegroundColor Red; exit 2 }
if ($Target -notmatch ':\d+$') { $Target = "${Target}:$Port" }

$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$ResDir = Join-Path $OutDir "board-results-$Stamp"
$ChkDir = Join-Path $ResDir 'checks'
$LibDir = Join-Path $ResDir 'libs'
$SysDir = Join-Path $ResDir 'sysinfo'
$TmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "ohjs-board-$Stamp"
foreach ($d in @($ResDir, $ChkDir, $LibDir, $SysDir, $TmpDir)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
$RemoteChk = "$RemoteDir/ohjs-chk"
$env:OHOS_HDC_SERVER_PORT = "$ServerPort"
$Results = New-Object System.Collections.ArrayList
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false
$Seq = 0

function Write-Utf8([string]$Path, [string]$Text) {
    [System.IO.File]::WriteAllText($Path, $Text, $Utf8NoBom)
}

function Quote-Arg([string]$a) {
    if ($a -eq '') { return '""' }
    if ($a -match '[\s"]') { return '"' + ($a -replace '"', '\"') + '"' }
    return $a
}

# Runs hdc with a timeout; returns @{ Out; Code; TimedOut; CmdLine }
function Invoke-Hdc([string[]]$HdcArgs, [int]$TimeoutSec = 120) {
    $all = @('-s', "127.0.0.1:$ServerPort") + $HdcArgs
    $argLine = ($all | ForEach-Object { Quote-Arg $_ }) -join ' '
    $id = [Guid]::NewGuid().ToString('N')
    $fo = Join-Path $TmpDir "$id.out"
    $fe = Join-Path $TmpDir "$id.err"
    $res = @{ Out = ''; Code = -1; TimedOut = $false; CmdLine = "hdc $argLine" }
    try {
        $p = Start-Process -FilePath $Hdc -ArgumentList $argLine -NoNewWindow -PassThru `
            -RedirectStandardOutput $fo -RedirectStandardError $fe
        $null = $p.Handle
        if (-not $p.WaitForExit($TimeoutSec * 1000)) {
            $res.TimedOut = $true
            try { $p.Kill() } catch { }
        } else {
            $res.Code = $p.ExitCode
        }
    } catch {
        $res.Out = "INVOKE ERROR: $($_.Exception.Message)"
        return $res
    }
    Start-Sleep -Milliseconds 100
    $o = ''
    foreach ($f in @($fo, $fe)) {
        if (Test-Path -LiteralPath $f) {
            try {
                # the hdc server forked by the first call may still hold these handles: share ReadWrite
                $st = New-Object System.IO.FileStream($f, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                $rd = New-Object System.IO.StreamReader($st)
                $o += $rd.ReadToEnd()
                $rd.Close()
            } catch { $o += "(cannot read $f)" }
        }
    }
    if ($res.TimedOut) { $o += "`n[TIMEOUT after $TimeoutSec s]" }
    $res.Out = $o
    return $res
}

function Add-Result([string]$Id, [string]$Status, [string]$Title, [string]$Note, [string]$File) {
    [void]$Results.Add([pscustomobject]@{ Id = $Id; Status = $Status; Title = $Title; Note = $Note; File = $File })
    $color = 'Gray'
    if ($Status -eq 'PASS') { $color = 'Green' } elseif ($Status -eq 'FAIL') { $color = 'Red' } elseif ($Status -eq 'INFO') { $color = 'Cyan' }
    Write-Host ("[{0,-4}] {1,-6} {2}  {3}" -f $Status, $Id, $Title, $Note) -ForegroundColor $color
}

function Save-Check([string]$Id, [string]$Title, [string]$CmdLine, [string]$Script, [string]$Output) {
    $script:Seq++
    $name = ('{0:D2}-{1}.txt' -f $script:Seq, $Id)
    $hdr = "# check:   $Id - $Title`n# target:  $Target`n# time:    $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')`n# command: $CmdLine`n"
    if ($Script) {
        $lines = @($Script -split "`n" | ForEach-Object { "#   $_" })
        $hdr += "# board script:`n" + ($lines -join "`n") + "`n"
    }
    Write-Utf8 (Join-Path $ChkDir $name) ($hdr + "# ---- output ----`n" + $Output + "`n")
    return "checks/$name"
}

# Host-side hdc command as a check
function Invoke-HostCheck([string]$Id, [string]$Title, [string[]]$HdcArgs, [scriptblock]$Judge, [int]$TimeoutSec = 60) {
    $r = Invoke-Hdc $HdcArgs $TimeoutSec
    $file = Save-Check $Id $Title $r.CmdLine '' $r.Out
    $v = & $Judge $r.Out
    Add-Result $Id $v[0] $Title $v[1] $file
    return $r
}

$script:DirectOnly = $false
# Board-side check: the sh script is sent as a file (no quoting issues) and run with `sh`.
function Invoke-BoardCheck([string]$Id, [string]$Title, [string]$Script, [scriptblock]$Judge, [int]$TimeoutSec = 120) {
    $Script = ($Script -replace "`r`n", "`n").Trim()
    $local = Join-Path $TmpDir "$Id.sh"
    Write-Utf8 $local ($Script + "`n")
    $r = $null
    if (-not $script:DirectOnly) {
        $s = Invoke-Hdc @('-t', $Target, 'file', 'send', $local, "$RemoteChk/$Id.sh") 120
        if ($s.Out -match '(?i)fail|error|not exist') { $script:DirectOnly = $true }
        else { $r = Invoke-Hdc @('-t', $Target, 'shell', "sh $RemoteChk/$Id.sh") $TimeoutSec }
    }
    if ($null -eq $r) {
        # fallback: single shell line
        $line = ($Script -split "`n" | Where-Object { $_ -notmatch '^\s*#' -and $_.Trim() }) -join '; '
        $r = Invoke-Hdc @('-t', $Target, 'shell', $line) $TimeoutSec
    }
    $file = Save-Check $Id $Title $r.CmdLine $Script $r.Out
    $v = $null
    try { $v = & $Judge $r.Out } catch { $v = @('INFO', "judge error: $($_.Exception.Message)") }
    Add-Result $Id $v[0] $Title $v[1] $file
    return $r.Out
}

function J([bool]$ok, [string]$pass, [string]$fail) { if ($ok) { return @('PASS', $pass) } else { return @('FAIL', $fail) } }

# Start the host hdc server up front, detached from our redirect files.
try {
    $sp = Start-Process -FilePath $Hdc -ArgumentList "-s 127.0.0.1:$ServerPort start" -NoNewWindow -PassThru
    $null = $sp.WaitForExit(15000)
} catch { Write-Host "WARN: could not pre-start hdc server: $($_.Exception.Message)" -ForegroundColor Yellow }

Write-Host "hdcd board check  target=$Target  hdc=$Hdc  server=127.0.0.1:$ServerPort"
Write-Host "results: $ResDir"
Write-Host ''

# ---------------------------------------------------------------- host + connect
$null = Invoke-HostCheck 'H0' 'host hdc version' @('-v') { param($o) if ($o -match 'Ver:\s*3\.2\.0c') { @('PASS', 'Ver 3.2.0c') } else { @('FAIL', 'host hdc must be 6.1-LTS (Ver: 3.2.0c)') } }
$tc = Invoke-HostCheck 'T1' 'tconn' @('tconn', $Target) { param($o) J ($o -match '(?i)Connect OK|already|is connected') 'Connect OK' 'no Connect OK (hdcd not running / firewall / IP?)' } 30
$null = Invoke-HostCheck 'T2' 'list targets -v' @('list', 'targets', '-v') { param($o) J ($o -match [regex]::Escape($Target) -and $o -match '(?i)Connected') 'target Connected' 'target not listed as Connected' }

$Reachable = $tc.Out -match '(?i)Connect OK|already|is connected'

# ---------------------------------------------------------------- optional upgrade
if ($Upgrade) {
    if (-not $Reachable) {
        Add-Result 'UPG' 'FAIL' 'upgrade hdcd' 'old hdcd not reachable; do the manual Step 0 from README first' ''
    } else {
        $bin = Join-Path $PackageDir 'hdcd.stripped'
        $para = Join-Path (Join-Path $PackageDir 'etc') 'hdcd.para'
        if (-not (Test-Path -LiteralPath $bin) -or -not (Test-Path -LiteralPath $para)) {
            Add-Result 'UPG' 'FAIL' 'upgrade hdcd' "package files missing under $PackageDir" ''
        } else {
            $null = Invoke-Hdc @('-t', $Target, 'shell', "mkdir -p $RemoteChk") 30
            $pick = Invoke-BoardCheck 'UPG0' 'upgrade: pick writable hdcd dir' @'
for d in /data/hdcd /data/local/tmp/hdcd /tmp/hdcd; do
  mkdir -p "$d" 2>/dev/null
  if touch "$d/.w" 2>/dev/null; then rm -f "$d/.w"; echo "HDCD_DIR=$d"; break; fi
done
'@ { param($o) if ($o -match 'HDCD_DIR=(\S+)') { @('INFO', $Matches[1]) } else { @('FAIL', 'no writable dir') } }
            if ($pick -match 'HDCD_DIR=(\S+)') {
                $hd = $Matches[1]
                $s1 = Invoke-Hdc @('-t', $Target, 'file', 'send', $bin, "$hd/hdcd.new") 600
                $s2 = Invoke-Hdc @('-t', $Target, 'file', 'send', $para, "$hd/hdcd.para") 60
                $f = Save-Check 'UPG1' 'upgrade: file send hdcd + hdcd.para' ($s1.CmdLine + ' ; ' + $s2.CmdLine) '' ($s1.Out + "`n" + $s2.Out)
                if (($s1.Out + $s2.Out) -match '(?i)fail|error') { Add-Result 'UPG1' 'FAIL' 'upgrade: file send hdcd + hdcd.para' 'send failed' $f }
                else { Add-Result 'UPG1' 'PASS' 'upgrade: file send hdcd + hdcd.para' "to $hd" $f }
                $start = $StartCmd.Replace('__DIR__', $hd)
                $restart = @'
D=__DIR__
chmod +x $D/hdcd.new && mv -f $D/hdcd.new $D/hdcd || { echo UPGRADE_COPY_FAILED; exit 1; }
ls -l $D/hdcd $D/hdcd.para
cat > $D/restart.sh <<'EOF'
sleep 2
for p in /proc/[0-9]*; do
  pid=${p#/proc/}
  [ "$pid" = "$$" ] && continue
  set -- $(tr '\0' ' ' < $p/cmdline 2>/dev/null)
  for a in "$1" "$2"; do
    case "${a##*/}" in hdcd|hdcd.stripped|hdcd.new) kill $pid 2>/dev/null; break;; esac
  done
done
sleep 2
cd __DIR__
__START__ > /tmp/hdcd.log 2>&1 < /dev/null &
EOF
if command -v setsid >/dev/null 2>&1; then setsid sh $D/restart.sh > /dev/null 2>&1 < /dev/null &
else nohup sh $D/restart.sh > /dev/null 2>&1 < /dev/null & fi
echo UPGRADE_SCHEDULED
'@
                $restart = $restart.Replace('__DIR__', $hd).Replace('__START__', $start)
                $null = Invoke-BoardCheck 'UPG2' 'upgrade: schedule restart' $restart { param($o) J ($o -match 'UPGRADE_SCHEDULED') 'restart scheduled' 'restart not scheduled' } 30
                Write-Host 'waiting for hdcd to restart ...'
                Start-Sleep -Seconds 6
                $ok = $false
                $log = ''
                for ($i = 0; $i -lt 10 -and -not $ok; $i++) {
                    $r = Invoke-Hdc @('tconn', $Target) 20
                    $log += $r.Out + "`n"
                    if ($r.Out -match '(?i)Connect OK|already|is connected') {
                        $e = Invoke-Hdc @('-t', $Target, 'shell', 'echo upgraded_ok') 20
                        $log += $e.Out + "`n"
                        if ($e.Out -match 'upgraded_ok') { $ok = $true; break }
                    }
                    Start-Sleep -Seconds 3
                }
                $f = Save-Check 'UPG3' 'upgrade: re-tconn' "hdc tconn $Target (retry)" '' $log
                if ($ok) { Add-Result 'UPG3' 'PASS' 'upgrade: re-tconn' "new hdcd from $hd answers" $f }
                else { Add-Result 'UPG3' 'FAIL' 'upgrade: re-tconn' 'board did not come back; check /tmp/hdcd.log via serial' $f }
                $Reachable = $ok
            }
        }
    }
}

if (-not $Reachable) {
    Write-Host 'Board not reachable - skipping board checks.' -ForegroundColor Red
} else {
    $null = Invoke-Hdc @('-t', $Target, 'shell', "mkdir -p $RemoteChk") 30

    # ------------------------------------------------------------ TCP checks (BOARD-CHECKLIST 3)
    $null = Invoke-BoardCheck 'T3' 'shell echo ok; uname -m' "echo ok; uname -m" { param($o) J ($o -match '(?m)^ok' -and $o -match 'loongarch64') 'ok / loongarch64' 'missing ok or loongarch64' }
    $null = Invoke-BoardCheck 'T4' 'exit code marker' 'false; echo __RC=$?' { param($o) J ($o -match '__RC=1') '__RC=1' 'expected __RC=1' }
    $null = Invoke-BoardCheck 'T5' 'running hdcd binary' @'
for p in /proc/[0-9]*; do
  set -- $(tr '\0' ' ' < $p/cmdline 2>/dev/null)
  for a in "$1" "$2"; do case "${a##*/}" in hdcd|hdcd.*) echo "pid ${p#/proc/}: $*"; f=$a;; esac; done
done
for f in /data/hdcd/hdcd /data/local/tmp/hdcd/hdcd /tmp/hdcd/hdcd; do
  [ -f "$f" ] && { ls -l "$f"; (sha256sum "$f" || md5sum "$f") 2>/dev/null; "$f" -v 2>&1 | head -2; }
done
'@ { param($o) if ($o -match 'Ver:\s*3\.2\.0c') { @('PASS', 'Ver 3.2.0c') } else { @('INFO', 'see file') } }

    # file round trip
    $big = Join-Path $TmpDir 'big.bin'
    $back = Join-Path $TmpDir 'big.back'
    $buf = New-Object byte[] (1MB)
    $rnd = New-Object System.Random
    $fs = [System.IO.File]::Create($big)
    for ($i = 0; $i -lt $BigFileMB; $i++) { $rnd.NextBytes($buf); $fs.Write($buf, 0, $buf.Length) }
    $fs.Close()
    $t0 = Get-Date
    $s = Invoke-Hdc @('-t', $Target, 'file', 'send', $big, "$RemoteDir/big.bin") 900
    $t1 = Get-Date
    $rv = Invoke-Hdc @('-t', $Target, 'file', 'recv', "$RemoteDir/big.bin", $back) 900
    $t2 = Get-Date
    $bs = Invoke-Hdc @('-t', $Target, 'shell', "ls -l $RemoteDir/big.bin; (sha256sum $RemoteDir/big.bin || md5sum $RemoteDir/big.bin) 2>/dev/null; rm -f $RemoteDir/big.bin") 120
    $h1 = (Get-FileHash -Algorithm SHA256 -LiteralPath $big).Hash.ToLower()
    $h2 = ''
    if (Test-Path -LiteralPath $back) { $h2 = (Get-FileHash -Algorithm SHA256 -LiteralPath $back).Hash.ToLower() }
    $txt = "$($s.CmdLine)`n$($s.Out)`n$($rv.CmdLine)`n$($rv.Out)`n$($bs.CmdLine)`n$($bs.Out)`nlocal sha256: $h1`nback  sha256: $h2`n"
    $txt += ('send {0:N1}s  recv {1:N1}s  size {2} MB' -f ($t1 - $t0).TotalSeconds, ($t2 - $t1).TotalSeconds, $BigFileMB)
    $f = Save-Check 'T6' "file send/recv $BigFileMB MB round trip" 'hdc file send / file recv / sha256' '' $txt
    if ($h2 -and $h1 -eq $h2) { Add-Result 'T6' 'PASS' "file send/recv $BigFileMB MB round trip" ('sha256 match (send {0:N1}s, recv {1:N1}s)' -f ($t1 - $t0).TotalSeconds, ($t2 - $t1).TotalSeconds) $f }
    else { Add-Result 'T6' 'FAIL' "file send/recv $BigFileMB MB round trip" 'hash mismatch or recv failed' $f }
    Remove-Item -LiteralPath $big, $back -Force -ErrorAction SilentlyContinue

    # fport
    $fp = Invoke-Hdc @('-t', $Target, 'fport', 'tcp:19001', 'tcp:5001') 30
    $fl = Invoke-Hdc @('-t', $Target, 'fport', 'ls') 30
    $fr = Invoke-Hdc @('-t', $Target, 'fport', 'rm', 'tcp:19001', 'tcp:5001') 30
    $f = Save-Check 'T7' 'fport tcp:19001 tcp:5001 / ls / rm' "$($fp.CmdLine) ; $($fl.CmdLine) ; $($fr.CmdLine)" '' "$($fp.Out)`n---`n$($fl.Out)`n---`n$($fr.Out)"
    $ok = ($fp.Out -match '(?i)OK') -and ($fl.Out -match 'tcp:19001')
    if ($ok) { Add-Result 'T7' 'PASS' 'fport tcp:19001 tcp:5001 / ls / rm' 'forward created and listed' $f } else { Add-Result 'T7' 'FAIL' 'fport tcp:19001 tcp:5001 / ls / rm' 'fport not OK or not listed' $f }

    # ------------------------------------------------------------ USB self-check (BOARD-CHECKLIST 6)
    $null = Invoke-BoardCheck 'U1' 'uname -a' 'uname -a' { param($o) J ($o -match '\b6\.6' -and $o -match 'loongarch64') 'kernel 6.6 loongarch64' 'expected 6.6 and loongarch64' }
    $null = Invoke-BoardCheck 'U2' 'ls /sys/class/udc' 'ls /sys/class/udc 2>&1' { param($o) J ($o.Trim() -ne '' -and $o -notmatch '(?i)No such') "UDC: $($o.Trim())" 'no UDC (no device controller / driver / not OTG device mode)' }
    $null = Invoke-BoardCheck 'U3' 'kernel config (USB gadget / configfs / functionfs)' @'
K="CONFIG_USB_GADGET CONFIG_USB_CONFIGFS CONFIG_USB_CONFIGFS_F_FS CONFIG_USB_FUNCTIONFS CONFIG_CONFIGFS_FS"
if [ -r /proc/config.gz ]; then SRC=/proc/config.gz; CAT="zcat /proc/config.gz"
elif [ -r /boot/config-$(uname -r) ]; then SRC=/boot/config-$(uname -r); CAT="cat $SRC"
elif ls /boot/config-* >/dev/null 2>&1; then SRC=$(ls /boot/config-* | head -1); CAT="cat $SRC"
else SRC=none; fi
echo "config source: $SRC"
if [ "$SRC" != none ]; then
  for k in $K; do v=$($CAT | grep -E "^$k=|^# $k is not set"); echo "$k -> ${v:-ABSENT}"; done
else
  echo "NO CONFIG: fallback checks"
  grep -E 'configfs|functionfs' /proc/filesystems
  ls -d /sys/kernel/config /sys/class/udc /sys/module/libcomposite /sys/module/usb_f_fs 2>&1
fi
'@ {
        param($o)
        if ($o -match 'NO CONFIG') {
            $ok = ($o -match 'configfs') -and ($o -match 'functionfs')
            if ($ok) { return @('PASS', 'NO CONFIG; fallback: configfs + functionfs present') }
            return @('INFO', 'NO CONFIG; fallback incomplete (see U7/U8)')
        }
        $miss = @()
        foreach ($k in @('CONFIG_USB_GADGET', 'CONFIG_USB_CONFIGFS', 'CONFIG_USB_CONFIGFS_F_FS', 'CONFIG_CONFIGFS_FS')) {
            if ($o -notmatch "$k=[ym]") { $miss += $k }
        }
        if ($miss.Count -eq 0) { return @('PASS', 'gadget/configfs/f_fs = y|m') }
        return @('FAIL', ('missing: ' + ($miss -join ',')))
    }
    $null = Invoke-BoardCheck 'U4' 'mounted configfs/functionfs' "mount | grep -E 'configfs|functionfs'" { param($o) if ($o -match 'type configfs') { @('PASS', 'configfs mounted') } else { @('INFO', 'not mounted (acceptable, recorded)') } }
    $null = Invoke-BoardCheck 'U5' 'ls /sys/kernel/config/usb_gadget' 'ls -l /sys/kernel/config/usb_gadget 2>&1' { param($o) J ($o -notmatch '(?i)No such') 'usb_gadget dir exists' 'configfs not mounted or CONFIG_USB_CONFIGFS off' }
    $null = Invoke-BoardCheck 'U6' 'writable dirs' @'
for d in /data /data/hdcd /tmp /etc /etc/hdcd; do
  mkdir -p "$d" 2>/dev/null
  if touch "$d/.hdcd_w" 2>/dev/null; then rm -f "$d/.hdcd_w"; echo "$d WRITABLE"; else echo "$d RO_OR_MISSING"; fi
done
df -h /data /tmp /etc 2>/dev/null
'@ {
        param($o)
        $ok = ($o -match '/data WRITABLE') -and ($o -match '/tmp WRITABLE')
        $etc = 'etc RO'
        if ($o -match '/etc WRITABLE') { $etc = 'etc writable' }
        if ($ok) { @('PASS', "/data,/tmp writable; $etc") } else { @('FAIL', "/data or /tmp not writable; $etc") }
    }
    $null = Invoke-BoardCheck 'U7' '/proc/filesystems configfs/functionfs' "grep -E 'configfs|functionfs' /proc/filesystems" { param($o) if (($o -match 'configfs') -and ($o -match 'functionfs')) { @('PASS', 'configfs + functionfs') } else { @('INFO', 'missing (module not loaded? see U3/U8)') } }
    $null = Invoke-BoardCheck 'U8' 'modules' "lsmod 2>/dev/null | grep -E 'usb_f_fs|libcomposite|configfs'; ls /lib/modules/`$(uname -r) 2>/dev/null | head" { param($o) @('INFO', 'recorded') }

    # ------------------------------------------------------------ 6b debug firmware (bm set)
    $null = Invoke-BoardCheck 'B1' 'bm set -s disable (debug firmware?)' 'bm set -s disable; echo __RC=$?' {
        param($o)
        if ($o -match '(?i)success') { @('PASS', 'debug firmware (OHOS_DEBUG): unsigned hap possible') }
        elseif ($o -match '(?i)fail') { @('INFO', 'debug firmware but BMS refused / not running') }
        elseif ($o -match '(?i)not found') { @('FAIL', 'bm not found') }
        else { @('INFO', 'release firmware (set subcommand missing): signed hap only') }
    }
    $null = Invoke-BoardCheck 'B2' 'bm set -d enable (optional)' 'bm set -d enable; echo __RC=$?' { param($o) if ($o -match '(?i)success') { @('PASS', 'success') } else { @('INFO', 'no success (see B1 rules)') } }

    # ------------------------------------------------------------ 6c hilogcat vs apphilogcat
    $null = Invoke-BoardCheck 'H1' 'hilogcat vs apphilogcat on /dev/hilog' @'
mkdir -p /tmp/ohjs
echo "== ps"; (ps -ef 2>/dev/null || ps) | grep -E '[a]pphilogcat|[h]ilogcat'
ls -l /dev/hilog /storage/data/log/ 2>&1
hilogcat > /tmp/ohjs/hilog.cap 2>&1 &
echo $! > /tmp/ohjs/hilogcat.pid
M=OHJSPROBE$(date +%s)
aa start -p $M -n ProbeAbility
sleep 3
kill $(cat /tmp/ohjs/hilogcat.pid) 2>/dev/null
echo "marker=$M"
echo "cap:  $(grep -c "$M" /tmp/ohjs/hilog.cap)"
echo "file: $(cat /storage/data/log/hilog*.txt 2>/dev/null | grep -c "$M")"
echo "cap lines: $(wc -l < /tmp/ohjs/hilog.cap)"; tail -5 /tmp/ohjs/hilog.cap
tail -5 /storage/data/log/hilog1.txt /storage/data/log/hilog2.txt 2>&1
'@ {
        param($o)
        $app = $o -match 'apphilogcat'
        $cap = 0; $fil = 0
        if ($o -match 'cap:\s+(\d+)') { $cap = [int]$Matches[1] }
        if ($o -match 'file:\s+(\d+)') { $fil = [int]$Matches[1] }
        if (-not $app) { return @('INFO', "apphilogcat not running: no contention, use hilogcat stream (cap=$cap file=$fil)") }
        if ($cap -ge 1 -and $fil -ge 1) { return @('INFO', "broadcast (cap=$cap file=$fil): use hilogcat stream") }
        if ($cap -ge 1 -or $fil -ge 1) { return @('INFO', "CONSUMING contention (cap=$cap file=$fil): IDE should tail hilog1.txt") }
        return @('INFO', 'marker not seen on either side: use the alternative check (BOARD-CHECKLIST 6c); file may need +10 s')
    } 60

    # ------------------------------------------------------------ misc board info (BOARD-CHECKLIST 7)
    $null = Invoke-BoardCheck 'I1' 'tools on PATH' 'which sh bm aa hilogcat 2>&1; echo PATH=$PATH' { param($o) @('INFO', 'recorded') }
    $null = Invoke-BoardCheck 'I2' 'hdcd log tail + persist.para' 'tail -50 /tmp/hdcd.log 2>&1; echo "== persist"; cat /data/hdcd/persist.para 2>&1' { param($o) @('INFO', 'recorded') }

    # ------------------------------------------------------------ ACE / jerry libs (JS-DEBUG.md B) - pull only
    $roots = ($LibSearchRoots | ForEach-Object { $_ }) -join ' '
    $libList = Invoke-BoardCheck 'L1' 'find libace_*.so / libjerry*.so' @"
for r in $roots; do
  find `$r \( -path /proc -o -path /sys -o -path /dev \) -prune -o \( -name 'libace_lite*.so*' -o -name 'libjerry*.so*' -o -name 'libace_*.so*' \) -print 2>/dev/null
done | sort -u > $RemoteChk/libs.txt
cat $RemoteChk/libs.txt
echo "== details"
while read f; do
  ls -l "`$f"
  (md5sum "`$f" || sha256sum "`$f") 2>/dev/null
  strings "`$f" 2>/dev/null | grep -m3 -E 'please connect to debugger server|JERRY|clang version|GCC'
done < $RemoteChk/libs.txt
"@ { param($o) if ($o -match '\.so') { @('PASS', 'libs found (pulled below)') } else { @('INFO', ('no ACE/jerry libs found under ' + $roots)) } } 600
    $paths = @()
    foreach ($line in ($libList -split "`r?`n")) {
        if ($line -match '^== details') { break }
        if ($line -match '^/\S+\.so') { $paths += $line.Trim() }
    }
    $pulled = 0; $failed = 0; $log = ''
    foreach ($p in $paths) {
        $local = Join-Path $LibDir (($p.TrimStart('/')) -replace '/', '__')
        $r = Invoke-Hdc @('-t', $Target, 'file', 'recv', $p, $local) 300
        $log += "$($r.CmdLine)`n$($r.Out)`n"
        if (Test-Path -LiteralPath $local) {
            $pulled++
            $log += ('  -> {0} bytes sha256 {1}' -f (Get-Item -LiteralPath $local).Length, (Get-FileHash -Algorithm SHA256 -LiteralPath $local).Hash.ToLower()) + "`n"
        } else { $failed++ }
    }
    $f = Save-Check 'L2' 'hdc file recv ACE/jerry libs' 'hdc file recv <each lib> libs/' '' $log
    if ($paths.Count -eq 0) { Add-Result 'L2' 'INFO' 'hdc file recv ACE/jerry libs' 'nothing to pull' $f }
    elseif ($failed -eq 0) { Add-Result 'L2' 'PASS' 'hdc file recv ACE/jerry libs' "$pulled file(s) pulled to libs/" $f }
    else { Add-Result 'L2' 'FAIL' 'hdc file recv ACE/jerry libs' "$pulled pulled, $failed failed" $f }

    # ------------------------------------------------------------ system info
    $null = Invoke-BoardCheck 'S1' 'release / cpu / mem / df' 'for f in /etc/*release /etc/*version; do [ -f "$f" ] && { echo "== $f"; cat "$f"; }; done; echo "== cpuinfo"; head -30 /proc/cpuinfo; echo "== meminfo"; head -5 /proc/meminfo; echo "== df"; df -h 2>/dev/null; echo "== mount"; mount' { param($o) @('INFO', 'recorded') }
    $null = Invoke-BoardCheck 'S2' 'dmesg tail' 'dmesg 2>&1 | tail -200' { param($o) @('INFO', 'recorded') }
    $cfg = Invoke-Hdc @('-t', $Target, 'shell', "if [ -r /proc/config.gz ]; then cp /proc/config.gz $RemoteChk/config.gz && echo CFG_COPIED; else echo NO_PROC_CONFIG; fi") 60
    $txt = "$($cfg.CmdLine)`n$($cfg.Out)`n"
    if ($cfg.Out -match 'CFG_COPIED') {
        $lc = Join-Path $SysDir 'config.gz'
        $r = Invoke-Hdc @('-t', $Target, 'file', 'recv', "$RemoteChk/config.gz", $lc) 120
        $txt += "$($r.CmdLine)`n$($r.Out)`n"
        $f = Save-Check 'S3' 'pull /proc/config.gz' 'cp /proc/config.gz + hdc file recv' '' $txt
        if (Test-Path -LiteralPath $lc) { Add-Result 'S3' 'PASS' 'pull /proc/config.gz' 'sysinfo/config.gz' $f } else { Add-Result 'S3' 'FAIL' 'pull /proc/config.gz' 'recv failed' $f }
    } else {
        $f = Save-Check 'S3' 'pull /proc/config.gz' $cfg.CmdLine '' $txt
        Add-Result 'S3' 'INFO' 'pull /proc/config.gz' 'not present' $f
    }
    foreach ($id in @('S1', 'S2')) {
        Get-ChildItem -LiteralPath $ChkDir -Filter "*-$id.txt" | Copy-Item -Destination $SysDir -ErrorAction SilentlyContinue
    }
    $null = Invoke-Hdc @('-t', $Target, 'shell', "rm -rf $RemoteChk") 30
}

# ---------------------------------------------------------------- summary + zip
$np = @($Results | Where-Object { $_.Status -eq 'PASS' }).Count
$nf = @($Results | Where-Object { $_.Status -eq 'FAIL' }).Count
$ni = @($Results | Where-Object { $_.Status -eq 'INFO' }).Count
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('hdcd board check summary')
[void]$sb.AppendLine("time:    $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')")
[void]$sb.AppendLine("target:  $Target")
[void]$sb.AppendLine("hdc:     $Hdc (server 127.0.0.1:$ServerPort)")
[void]$sb.AppendLine("upgrade: $([bool]$Upgrade)")
[void]$sb.AppendLine("host:    $([Environment]::OSVersion.VersionString), PowerShell $($PSVersionTable.PSVersion)")
[void]$sb.AppendLine("totals:  PASS=$np FAIL=$nf INFO=$ni")
[void]$sb.AppendLine('')
[void]$sb.AppendLine(('{0,-6} {1,-5} {2,-48} {3,-26} {4}' -f 'ID', 'STAT', 'CHECK', 'FILE', 'NOTE'))
[void]$sb.AppendLine(('-' * 130))
foreach ($r in $Results) {
    [void]$sb.AppendLine(('{0,-6} {1,-5} {2,-48} {3,-26} {4}' -f $r.Id, $r.Status, $r.Title, $r.File, $r.Note))
}
Write-Utf8 (Join-Path $ResDir 'Summary.txt') $sb.ToString()
$Results | Export-Csv -NoTypeInformation -Path (Join-Path $ResDir 'Summary.csv') -Encoding UTF8
Remove-Item -LiteralPath $TmpDir -Recurse -Force -ErrorAction SilentlyContinue

$Zip = Join-Path $OutDir "board-results-$Stamp.zip"
try {
    Compress-Archive -Path (Join-Path $ResDir '*') -DestinationPath $Zip -Force -ErrorAction Stop
} catch {
    Write-Host "ERROR: Compress-Archive failed: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ''
Write-Host "PASS=$np FAIL=$nf INFO=$ni"
Write-Host "Summary: $(Join-Path $ResDir 'Summary.txt')"
Write-Host "Results zip: $Zip" -ForegroundColor Yellow
if ($nf -gt 0) { exit 1 } else { exit 0 }
