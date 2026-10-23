#!/bin/bash
# End-to-end: board-results-*.zip → unpack → abi-compare → optional BOARD_NEEDED
# relink + re-compare → pack-debug-libs → print next steps for Sam.
#
# Usage:
#   from-board-results.sh board-results-….zip [--ours DIR] [--work DIR] [--keep]
#   from-board-results.sh --board-results ZIP [--ours DIR] [--work DIR]
#
# Exit 0 = packed (or YES with pack); non-zero = stopped at a stage (work dir kept).
# Intermediates always left under --work (default /tmp/from-board-results-<ts>).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
PORT=${PORT:-/workspace/hdcd-port}
OURS_DEFAULT="$PORT/b/acelite-la64"
OURS="$OURS_DEFAULT"
ZIP=""
WORK=""
KEEP=1   # always keep on failure; --keep also keeps on success (default keep always for Sam)

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --board-results) ZIP=$2; shift 2 ;;
    --ours) OURS=$2; shift 2 ;;
    --work) WORK=$2; shift 2 ;;
    --keep) KEEP=1; shift ;;
    -h|--help) usage ;;
    *.zip) ZIP=$1; shift ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done
[ -n "$ZIP" ] || { echo "need board-results zip" >&2; usage; }
[ -f "$ZIP" ] || { echo "zip not found: $ZIP" >&2; exit 2; }
[ -d "$OURS" ] || { echo "ours dir missing: $OURS" >&2; exit 2; }

TS=$(date +%Y%m%d-%H%M%S)
WORK=${WORK:-/tmp/from-board-results-$TS}
mkdir -p "$WORK"
ZIP_ABS=$(cd "$(dirname "$ZIP")" && pwd)/$(basename "$ZIP")
cp -a "$ZIP_ABS" "$WORK/board-results.zip"
echo "Work dir: $WORK" >&2
echo "Ours: $OURS" >&2

stage() { echo ""; echo "==== STAGE: $* ====" >&2; }
fail_stage() {
  echo "" >&2
  echo "STOPPED at stage: $1 (exit $2)" >&2
  echo "Intermediates kept under: $WORK" >&2
  echo "  unpack/   abi-report*/   relink/   pack/   as applicable" >&2
  exit "$2"
}

# ---- 1 unpack ----
stage "unpack"
LIBS=$("$HERE/unpack-board-results.sh" "$WORK/board-results.zip" "$WORK/unpack" 2>"$WORK/unpack.log" | tail -n1) || true
if [ -z "$LIBS" ] || [ ! -d "$LIBS" ]; then
  echo "unpack failed; see $WORK/unpack.log" >&2
  cat "$WORK/unpack.log" >&2 || true
  fail_stage unpack 1
fi
echo "libs: $LIBS" >&2
echo "$LIBS" > "$WORK/libs.path"

# ---- 2 abi-compare ----
stage "abi-compare"
REP1="$WORK/abi-report-1"
mkdir -p "$REP1"
set +e
"$HERE/abi-compare.sh" --board-libs "$LIBS" --ours "$OURS" --out "$REP1" >"$WORK/abi-compare-1.out" 2>"$WORK/abi-compare-1.err"
rc1=$?
set -e
cp -a "$WORK/abi-compare-1.out" "$REP1/" 2>/dev/null || true
if [ ! -f "$REP1/abi-report.json" ]; then
  echo "abi-compare produced no report (rc=$rc1)" >&2
  cat "$WORK/abi-compare-1.err" >&2 || true
  fail_stage abi-compare 1
fi

verdict_of() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["recommendation"]["verdict"])' "$1"
}
class_of() {
  python3 -c '
import sys
v=sys.argv[1]
if v.startswith("YES"): print("YES")
elif v.startswith("NO") or v[:8].startswith("NO"): print("NO")
elif "BOARD_NEEDED" in v or "relink" in v.lower(): print("NEED_RELINK")
elif v.startswith("CONDITIONAL"): print("CONDITIONAL_WARN")
else: print("UNKNOWN")
' "$1"
}
board_needed_of() {
  # Prefer board-only NEEDED list from report artifacts; else parse detail.
  python3 -c '
import json,sys,re,os
rep=sys.argv[1]
d=json.load(open(rep))
# from results
needed=[]
for r in d.get("results",[]):
    if r.get("check")=="needed" and r.get("status")=="WARN" and "board-only NEEDED" in r.get("detail",""):
        m=re.search(r"board-only NEEDED[^:]*:\s*(.*)$", r["detail"])
        if m:
            needed=m.group(1).split()
            break
if not needed:
    det=d.get("recommendation",{}).get("detail","")
    m=re.search(r"needs:\s*([^.]+)", det)
    if m: needed=m.group(1).split()
# strip trailing empties
print(" ".join(x for x in needed if x.strip()))
' "$1"
}

V1=$(verdict_of "$REP1/abi-report.json")
C1=$(class_of "$V1")
echo "Verdict #1: $V1 ($C1)" >&2
echo "$V1" > "$WORK/verdict-1.txt"
USED_RELINK=0
AFTER_RELINK_FLAG=()

# ---- 3 optional BOARD_NEEDED relink ----
if [ "$C1" = "NEED_RELINK" ]; then
  stage "relink-board-needed"
  BN=$(board_needed_of "$REP1/abi-report.json")
  if [ -z "$BN" ]; then
    echo "CONDITIONAL BOARD_NEEDED but could not parse soname list" >&2
    fail_stage relink 1
  fi
  echo "BOARD_NEEDED=$BN" >&2
  echo "$BN" > "$WORK/BOARD_NEEDED.txt"
  mkdir -p "$WORK/relink"
  set +e
  BOARD_NEEDED="$BN" OUT="$OURS" "$HERE/relink-board-needed.sh" >"$WORK/relink/relink.out" 2>"$WORK/relink/relink.err"
  rcr=$?
  set -e
  if [ "$rcr" != 0 ]; then
    echo "relink failed rc=$rcr" >&2
    cat "$WORK/relink/relink.err" >&2 || true
    fail_stage relink "$rcr"
  fi
  USED_RELINK=1
  AFTER_RELINK_FLAG=(--after-relink)

  stage "abi-compare (after relink)"
  REP2="$WORK/abi-report-2"
  mkdir -p "$REP2"
  set +e
  "$HERE/abi-compare.sh" --board-libs "$LIBS" --ours "$OURS" --out "$REP2" >"$WORK/abi-compare-2.out" 2>"$WORK/abi-compare-2.err"
  rc2=$?
  set -e
  if [ ! -f "$REP2/abi-report.json" ]; then
    fail_stage abi-compare-2 1
  fi
  V2=$(verdict_of "$REP2/abi-report.json")
  C2=$(class_of "$V2")
  echo "Verdict #2: $V2 ($C2)" >&2
  echo "$V2" > "$WORK/verdict-2.txt"
  FINAL_REP="$REP2"
  FINAL_V="$V2"
  FINAL_C="$C2"
else
  FINAL_REP="$REP1"
  FINAL_V="$V1"
  FINAL_C="$C1"
fi

case "$FINAL_C" in
  YES|CONDITIONAL_WARN) ;;
  NEED_RELINK)
    echo "Still NEED_RELINK after relink — refuse pack" >&2
    fail_stage pack 1
    ;;
  NO|*)
    echo "Final verdict not packable: $FINAL_V" >&2
    fail_stage pack 1
    ;;
esac

# ---- 4 pack ----
stage "pack-debug-libs"
PACK_OUT="$WORK/pack"
mkdir -p "$PACK_OUT"
set +e
ZIP_OUT=$("$HERE/pack-debug-libs.sh" --report "$FINAL_REP" --ours "$OURS" --out "$PACK_OUT" "${AFTER_RELINK_FLAG[@]}" 2>"$WORK/pack.err")
rcp=$?
set -e
PACK_ZIP=$(printf '%s\n' "$ZIP_OUT" | tail -n1)
if [ "$rcp" != 0 ] || [ -z "$PACK_ZIP" ] || [ ! -f "$PACK_ZIP" ]; then
  echo "pack failed rc=$rcp" >&2
  cat "$WORK/pack.err" >&2 || true
  fail_stage pack 1
fi
echo "$PACK_ZIP" > "$WORK/debug-libs.path"
echo "Packed: $PACK_ZIP" >&2

# ---- 5 next steps ----
cat <<NEXT

========================================================================
NEXT STEPS for Sam
========================================================================
1. Download the debug-libs zip:
     $PACK_ZIP
   (work dir: $WORK)

2. Unzip on the Windows host next to hdc.exe / board tools.

3. Review swap-libs.ps1 (PRINT-ONLY by default — no remount, no overwrite):
     powershell -ExecutionPolicy Bypass -File .\swap-libs.ps1 -Target <board-IP>
   Read BACKUP-AND-ROLLBACK.md in the zip first.

4. Only after you confirm the printed hdc/shell steps, run dangerous ops:
     powershell -ExecutionPolicy Bypass -File .\swap-libs.ps1 -Target <board-IP> -Execute
   Remount + install into the system lib dir additionally needs:
     ... -Execute -DoRemount -RemoteLibDir <board-lib-dir>
   Never pass -DoRemount without reviewing the mount and keeping a system image.

5. Final ABI verdict was:
     $FINAL_V
   Relink used: $USED_RELINK
========================================================================
NEXT

echo "$PACK_ZIP"
exit 0
