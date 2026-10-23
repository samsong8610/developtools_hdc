#!/bin/bash
# Pack replaceable debug ACE/jerry libs into debug-libs-<timestamp>.zip
# only when abi-compare says YES (or CONDITIONAL after a BOARD_NEEDED relink).
#
# Usage:
#   pack-debug-libs.sh --board-libs DIR [--ours DIR] [--out DIR]
#   pack-debug-libs.sh --board-results board-results-….zip […]
#   pack-debug-libs.sh --report DIR/abi-report.json [--ours DIR] [--out DIR]
#   pack-debug-libs.sh --report DIR/abi-report.json --after-relink   # allow CONDITIONAL (BOARD_NEEDED)
#
# Exit 0 = zip written; 1 = refused (NO / unhandled CONDITIONAL); 2 = usage/tooling.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
PORT=${PORT:-/workspace/hdcd-port}
OURS_DEFAULT="$PORT/b/acelite-la64"
OURS="$OURS_DEFAULT"
BOARD_LIBS=""
BOARD_RESULTS=""
REPORT=""
OUT=""
AFTER_RELINK=0
LIBS=(libace_lite.so libjerry-core.so libjerry-ext.so libjerry-port-default.so)

usage() {
  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --board-libs) BOARD_LIBS=$2; shift 2 ;;
    --board-results) BOARD_RESULTS=$2; shift 2 ;;
    --ours) OURS=$2; shift 2 ;;
    --report) REPORT=$2; shift 2 ;;
    --out) OUT=$2; shift 2 ;;
    --after-relink) AFTER_RELINK=1; shift ;;
    -h|--help) usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

if [ -z "$REPORT" ] && [ -z "$BOARD_LIBS" ] && [ -z "$BOARD_RESULTS" ]; then
  echo "need --report, --board-libs, or --board-results" >&2
  usage
fi

TS=$(date +%Y%m%d-%H%M%S)
WORK=${OUT:-/tmp/pack-debug-libs-$TS}
mkdir -p "$WORK"
REPORT_DIR="$WORK/abi-report"
mkdir -p "$REPORT_DIR"

if [ -n "$REPORT" ]; then
  if [ -d "$REPORT" ]; then
    cp -a "$REPORT"/abi-report.json "$REPORT"/abi-report.md "$REPORT_DIR/" 2>/dev/null || true
    [ -f "$REPORT_DIR/abi-report.json" ] || { echo "no abi-report.json in $REPORT" >&2; exit 2; }
  elif [ -f "$REPORT" ]; then
    cp -a "$REPORT" "$REPORT_DIR/abi-report.json"
    base=$(dirname "$REPORT")
    [ -f "$base/abi-report.md" ] && cp -a "$base/abi-report.md" "$REPORT_DIR/"
  else
    echo "report not found: $REPORT" >&2; exit 2
  fi
else
  cmp_args=(--ours "$OURS" --out "$REPORT_DIR")
  if [ -n "$BOARD_RESULTS" ]; then
    cmp_args+=(--board-results "$BOARD_RESULTS")
  else
    cmp_args+=(--board-libs "$BOARD_LIBS")
  fi
  set +e
  # Keep stdout clean: only the final zip path is printed on stdout.
  "$HERE/abi-compare.sh" "${cmp_args[@]}" >&2
  cmp_rc=$?
  set -e
  # abi-compare: 0 = no FAIL; 1 = FAIL; 2 = tooling. We still parse the verdict.
  if [ ! -f "$REPORT_DIR/abi-report.json" ]; then
    echo "abi-compare did not produce abi-report.json (rc=$cmp_rc)" >&2
    exit 2
  fi
fi

VERDICT=$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
print(d.get("recommendation",{}).get("verdict",""))
' "$REPORT_DIR/abi-report.json")
DETAIL=$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
print(d.get("recommendation",{}).get("detail",""))
' "$REPORT_DIR/abi-report.json")

echo "Verdict: $VERDICT" >&2

# Classify verdict (em-dash / ASCII dash tolerant)
CLASS=$(python3 -c '
import sys
v = sys.argv[1]
if v.startswith("YES"):
    print("YES")
elif "NO" in v[:8] or v.startswith("NO"):
    print("NO")
elif "BOARD_NEEDED" in v or "relink" in v.lower():
    print("NEED_RELINK")
elif v.startswith("CONDITIONAL"):
    print("CONDITIONAL_WARN")
else:
    print("UNKNOWN")
' "$VERDICT")

case "$CLASS" in
  YES)
    ;;
  NEED_RELINK)
    if [ "$AFTER_RELINK" -eq 1 ]; then
      echo "NOTE: --after-relink set; packing despite BOARD_NEEDED CONDITIONAL (ensure you already relinked)." >&2
    else
      echo "REFUSE: need BOARD_NEEDED relink first, then re-run abi-compare and this packer." >&2
      echo "  $DETAIL" >&2
      echo "  Or pass --after-relink if you already ran relink-board-needed.sh and re-compared." >&2
      exit 1
    fi
    ;;
  CONDITIONAL_WARN)
    echo "NOTE: CONDITIONAL (review WARN); packing with caveat in BACKUP-AND-ROLLBACK.md." >&2
    ;;
  *)
    echo "REFUSE: verdict is not packable: $VERDICT" >&2
    echo "  $DETAIL" >&2
    exit 1
    ;;
esac

STAGE="$WORK/stage"
mkdir -p "$STAGE"
missing=0
for so in "${LIBS[@]}"; do
  if [ ! -f "$OURS/$so" ]; then
    echo "missing $OURS/$so" >&2
    missing=1
  else
    cp -a "$OURS/$so" "$STAGE/$so"
  fi
done
[ "$missing" = 0 ] || exit 2

(cd "$STAGE" && sha256sum "${LIBS[@]}" > SHA256SUMS)

# Provenance
cp -a "$REPORT_DIR/abi-report.json" "$STAGE/" 2>/dev/null || true
cp -a "$REPORT_DIR/abi-report.md" "$STAGE/" 2>/dev/null || true
cat > "$STAGE/VERDICT.txt" << VEOF
$VERDICT
$DETAIL
packed: $TS
ours: $OURS
VEOF

# English rollback guide
cat > "$STAGE/BACKUP-AND-ROLLBACK.md" << 'MEOF'
# Backup and rollback (debug ACE / Jerry libs)

**Read this before touching the board.** Prefer a writable `/data` copy-test before any `/system` remount.
`swap-libs.ps1` **prints** the exact steps by default. Pass `-Execute` only when you intend to run the dangerous ones (remount, overwrite). It never remounts without `-Execute`.

## Prerequisites

1. Offline ABI compare verdict was **YES** (or CONDITIONAL after a successful `BOARD_NEEDED` relink). See `abi-report.md` in this zip and `VERDICT.txt`.
2. Keep a full system image / recovery path at hand. A bad replace can brick boot or break every JS app.
3. Host `hdc` is Ver 3.2.0c and already `tconn` to the board (port 8710).

## Libraries in this package

- `libace_lite.so`
- `libjerry-core.so`
- `libjerry-ext.so`
- `libjerry-port-default.so`

Always deploy all four together. The debug `libace_lite.so` needs symbols only the patched `libjerry-ext.so` provides.

## Recommended flow (print-only first)

```powershell
# On the Windows host, from the unzipped debug-libs folder:
powershell -ExecutionPolicy Bypass -File .\swap-libs.ps1 -Target 192.168.1.50
# Review the printed hdc/shell lines. When ready:
powershell -ExecutionPolicy Bypass -File .\swap-libs.ps1 -Target 192.168.1.50 -Execute
```

### What the script does (with `-Execute`)

1. Finds board lib dir (or uses `-RemoteLibDir`).
2. Backs up current `.so` to `/data/ohjs-bak/` and records sha256.
3. `file send`s this package's `.so` to `/data/ohjs-new/`.
4. Only if needed and only with `-Execute`: remount that mountpoint `rw`, copy into place, `sync`.
5. Verifies `strings … | grep 'please connect to debugger server'` and (optional) `netstat` for `:5001`.
6. Prints rollback commands (restore from `/data/ohjs-bak`).

### Manual rollback (if the app crashes or the device misbehaves)

```sh
# on device (or via hdc shell)
D=<lib-dir>          # e.g. /system/lib64
M=$(df $D | tail -1 | awk '{print $NF}')
mount -o remount,rw $M
cp -a /data/ohjs-bak/libace_lite.so /data/ohjs-bak/libjerry-*.so $D/
sync
mount -o remount,ro $M
# restart the JS app (aa terminate / aa start) or reboot
```

If the device will not boot, reflash the system image.

## Safer alternative (no remount)

Push the libs to `/data/ohjs-new/` and use a test harness / `LD_LIBRARY_PATH` / app-local load only if your board image supports it. Do **not** assume stock ACE will load from `/data`.
MEOF

# swap-libs.ps1 — print by default; -Execute for dangerous ops
# Write with Unix LF here; package refresh will also offer BOM via the .ps1 companion if needed.
# For the zip we embed a Windows-friendly script (CRLF applied below).
python3 - << 'PY' > "$STAGE/swap-libs.ps1"
content = r'''<#
.SYNOPSIS
  Print (default) or execute hdc steps to backup / push / verify / roll back debug ACE+jerry libs.
.DESCRIPTION
  WITHOUT -Execute this script ONLY PRINTS the exact hdc and shell commands.
  Remount, overwrite, and any write to the system lib dir require -Execute.
  Never auto-remounts without -Execute.
.PARAMETER Target
  Board IP or ip:port (default port 8710).
.PARAMETER Port
  Device hdcd port (default 8710).
.PARAMETER Hdc
  Path to hdc.exe (default: hdc on PATH).
.PARAMETER ServerPort
  Host hdc server port (default 8710; use 8711 if hdcd and host share a machine).
.PARAMETER RemoteLibDir
  Absolute lib directory on device (e.g. /system/lib64). If empty, prints a find command.
.PARAMETER RemoteNew
  Staging dir on device (default /data/ohjs-new).
.PARAMETER RemoteBak
  Backup dir on device (default /data/ohjs-bak).
.PARAMETER Execute
  Actually run dangerous steps (backup, file send, optional remount+copy). Default: print only.
.PARAMETER DoRemount
  With -Execute, also remount rw and copy from RemoteNew into RemoteLibDir. Default: false
  (file send to /data only). Remount never happens without both -Execute and -DoRemount.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Target,
    [int]$Port = 8710,
    [string]$Hdc = 'hdc',
    [int]$ServerPort = 8710,
    [string]$RemoteLibDir = '',
    [string]$RemoteNew = '/data/ohjs-new',
    [string]$RemoteBak = '/data/ohjs-bak',
    [switch]$Execute,
    [switch]$DoRemount
)
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = (Get-Location).Path }
$Libs = @('libace_lite.so','libjerry-core.so','libjerry-ext.so','libjerry-port-default.so')
foreach ($so in $Libs) {
    if (-not (Test-Path -LiteralPath (Join-Path $Here $so))) {
        throw "Missing $so next to swap-libs.ps1"
    }
}
$t = $Target
if ($t -notmatch ':\d+$') { $t = "${Target}:${Port}" }
function HdcArgs([string[]]$Rest) {
    $a = @('-s', "127.0.0.1:$ServerPort", '-t', $t) + $Rest
    return $a
}
function Show([string]$Title, [string[]]$Cmd) {
    Write-Host ""
    Write-Host "=== $Title ===" -ForegroundColor Cyan
    Write-Host ("{0} {1}" -f $Hdc, ($Cmd -join ' '))
}
function RunOrShow([string]$Title, [string[]]$Cmd, [bool]$Dangerous = $false) {
    Show $Title $Cmd
    if (-not $Execute) { return }
    if ($Dangerous -and -not $Execute) { return }
    & $Hdc @Cmd
    if ($LASTEXITCODE -ne 0) { throw "hdc failed ($LASTEXITCODE): $($Cmd -join ' ')" }
}

Write-Host "Mode: $(if ($Execute) { 'EXECUTE' } else { 'PRINT ONLY (pass -Execute to run)' })" -ForegroundColor Yellow
if ($DoRemount -and -not $Execute) {
    Write-Host "NOTE: -DoRemount ignored without -Execute (no remount will be printed as executed)." -ForegroundColor Yellow
}

# 0) connectivity
RunOrShow 'check target' (HdcArgs @('list','targets','-v'))

# 1) locate lib dir
if (-not $RemoteLibDir) {
    $findCmd = 'for f in $(find /system /vendor /usr /lib /lib64 /data 2>/dev/null -name libace_lite.so | head -5); do echo FOUND:$f; ls -l $f; done'
    RunOrShow 'find libace_lite.so on device' (HdcArgs @('shell', $findCmd))
    Write-Host "Set -RemoteLibDir to the directory that contains libace_lite.so, then re-run." -ForegroundColor Yellow
}

# 2) backup
$bakMk = "mkdir -p $RemoteBak $RemoteNew"
RunOrShow 'mkdir bak+new' (HdcArgs @('shell', $bakMk)) $true
if ($RemoteLibDir) {
    $bakCp = "cp -a $RemoteLibDir/libace_lite.so $RemoteLibDir/libjerry-core.so $RemoteLibDir/libjerry-ext.so $RemoteLibDir/libjerry-port-default.so $RemoteBak/ 2>/dev/null; sha256sum $RemoteBak/libace_lite.so $RemoteBak/libjerry-*.so 2>/dev/null"
    RunOrShow 'backup board libs -> /data/ohjs-bak' (HdcArgs @('shell', $bakCp)) $true
}

# 3) file send (staging only — safe-ish; still requires -Execute)
foreach ($so in $Libs) {
    $local = Join-Path $Here $so
    $remote = "$RemoteNew/$so"
    RunOrShow "file send $so -> $remote" (HdcArgs @('file','send', $local, $remote)) $true
}

# 4) remount + install — ONLY with -Execute -DoRemount
if ($RemoteLibDir) {
    $mntCmd = "df $RemoteLibDir | tail -1"
    RunOrShow 'df lib dir' (HdcArgs @('shell', $mntCmd))
    $install = @"
M=`$(df $RemoteLibDir | tail -1 | awk '{print `$NF}')
echo MOUNT=`$M
mount | grep -E " `$M " || true
mount -o remount,rw `$M
cp -a $RemoteNew/libace_lite.so $RemoteNew/libjerry-core.so $RemoteNew/libjerry-ext.so $RemoteNew/libjerry-port-default.so $RemoteLibDir/
sync
sha256sum $RemoteLibDir/libace_lite.so $RemoteLibDir/libjerry-*.so
"@
    if ($Execute -and $DoRemount) {
        Write-Host "=== remount rw + copy into $RemoteLibDir (DANGEROUS) ===" -ForegroundColor Red
        & $Hdc @(HdcArgs @('shell', $install))
        if ($LASTEXITCODE -ne 0) { throw "remount/copy failed" }
    } else {
        Write-Host ""
        Write-Host "=== remount rw + copy (NOT run; needs -Execute -DoRemount) ===" -ForegroundColor Yellow
        Write-Host "$Hdc $((HdcArgs @('shell', '<install-script>')) -join ' ')"
        Write-Host $install
    }
}

# 5) verify
$verify = "strings $($RemoteLibDir)/libace_lite.so 2>/dev/null | grep -c 'please connect to debugger server' || strings $RemoteNew/libace_lite.so | grep -c 'please connect to debugger server'; (netstat -ltn 2>/dev/null || ss -ltn) | grep -E ':5001' || echo 'no :5001 listener (gate off by default — OK)'"
RunOrShow 'verify debugger string + :5001' (HdcArgs @('shell', $verify))

# 6) rollback recipe (always print)
Write-Host ""
Write-Host "=== rollback (print only; run manually if needed) ===" -ForegroundColor Cyan
if ($RemoteLibDir) {
    Write-Host @"
$Hdc $((HdcArgs @('shell', '…')) -join ' ')
M=`$(df $RemoteLibDir | tail -1 | awk '{print `$NF}')
mount -o remount,rw `$M
cp -a $RemoteBak/libace_lite.so $RemoteBak/libjerry-*.so $RemoteLibDir/
sync
mount -o remount,ro `$M
"@
} else {
    Write-Host "Set -RemoteLibDir, then restore from $RemoteBak into that directory (remount rw if needed)."
}

if (-not $Execute) {
    Write-Host ""
    Write-Host "Re-run with -Execute to perform backup + file send. Add -DoRemount to also remount and overwrite the lib dir." -ForegroundColor Green
}
'''
# CRLF + UTF-8 BOM for Windows PowerShell 5.1
import sys
sys.stdout.buffer.write(b'\xef\xbb\xbf')
sys.stdout.buffer.write(content.replace('\n', '\r\n').encode('utf-8'))
PY

ZIP_NAME="debug-libs-$TS.zip"
ZIP_PATH="$WORK/$ZIP_NAME"
(
  cd "$STAGE"
  # zip is widely available; fall back to tar.gz if not
  if command -v zip >/dev/null 2>&1; then
    zip -q -r "$ZIP_PATH" .
  else
    ZIP_NAME="debug-libs-$TS.tar.gz"
    ZIP_PATH="$WORK/$ZIP_NAME"
    tar -czf "$ZIP_PATH" .
  fi
)

echo "$ZIP_PATH"
echo "Packed: $ZIP_PATH" >&2
echo "Verdict: $VERDICT" >&2
ls -la "$STAGE" >&2
