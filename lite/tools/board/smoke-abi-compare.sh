#!/bin/bash
# Build tiny fixtures from b/acelite-la64 and run abi-compare.sh smoke cases.
# Exit 0 only if all expected verdicts match.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
PORT=${PORT:-/workspace/hdcd-port}
O=${OURS:-$PORT/b/acelite-la64}
FIX=${FIXDIR:-/tmp/abi-fixtures-$$}
OUT=${OUTDIR:-/tmp/abi-smoke-$$}
mkdir -p "$FIX/good" "$FIX/bad-machine" "$FIX/ours-extra" "$FIX/ziproot/libs" "$OUT"
cleanup() { rm -rf "$FIX"; }
trap cleanup EXIT

[ -f "$O/libace_lite.so" ] || { echo "missing $O/libace_lite.so — build first" >&2; exit 2; }
cp -a "$O"/libace_lite.so "$O"/libjerry-*.so "$FIX/good/"
cp -a "$O"/libjerry-*.so "$FIX/bad-machine/"
echo 'void ace_stub(void){}' | cc -shared -fPIC -o "$FIX/bad-machine/libace_lite.so" -x c - -Wl,-soname,libace_lite.so
# relink with extra NEEDED into ours-extra
rm -rf /tmp/ace-relink-smoke
mkdir -p /tmp/ace-relink-smoke
ln -s "$O/obj" /tmp/ace-relink-smoke/obj
ln -s "$O/libjerry-core.so" "$O/libjerry-ext.so" "$O/libjerry-port-default.so" /tmp/ace-relink-smoke/
OUT=/tmp/ace-relink-smoke BOARD_NEEDED="libui.so libhilog_shared.so" "$HERE/relink-board-needed.sh" >/tmp/ace-relink-smoke.log
cp -a /tmp/ace-relink-smoke/libace_lite.so "$FIX/ours-extra/"
cp -a "$O"/libjerry-*.so "$FIX/ours-extra/"
# zip-like layout with board-check naming
for n in libace_lite.so libjerry-core.so libjerry-ext.so libjerry-port-default.so; do
  cp "$O/$n" "$FIX/ziproot/libs/system__lib__$n"
done
echo fake > "$FIX/ziproot/libs/system__lib__libace_native_engine.so"
echo ok > "$FIX/ziproot/Summary.txt"
python3 - <<P
import zipfile,os
z=os.path.join("$FIX","sample.zip")
with zipfile.ZipFile(z,"w") as zf:
  for dp,_,fs in os.walk("$FIX/ziproot"):
    for f in fs:
      p=os.path.join(dp,f); zf.write(p, os.path.relpath(p,"$FIX"))
print(z)
P

fail=0
check() {
  local label=$1 expect=$2; shift 2
  local o="$OUT/$label"
  mkdir -p "$o"
  set +e
  "$@" --out "$o" >"$o/run.log" 2>&1
  local rc=$?
  set -e
  local rec
  rec=$(grep -E 'Recommendation:' "$o/run.log" | tail -1 || true)
  echo "[$label] rc=$rc $rec"
  if ! grep -q "$expect" "$o/run.log"; then
    echo "  FAIL expected /$expect/" >&2
    tail -20 "$o/run.log" >&2
    fail=1
  fi
}

check identical 'YES' "$HERE/abi-compare.sh" --board-libs "$FIX/good" --ours "$O"
check bad-machine 'NO' "$HERE/abi-compare.sh" --board-libs "$FIX/bad-machine" --ours "$O"
check needed-ours 'CONDITIONAL — review' "$HERE/abi-compare.sh" --board-libs "$FIX/good" --ours "$FIX/ours-extra"
check needed-board 'CONDITIONAL — relink with BOARD_NEEDED' "$HERE/abi-compare.sh" --board-libs "$FIX/ours-extra" --ours "$O"
check from-zip 'YES' "$HERE/abi-compare.sh" --board-results "$FIX/sample.zip" --ours "$O"

if [ "$fail" -eq 0 ]; then echo "SMOKE PASS (reports under $OUT)"; exit 0; else echo "SMOKE FAIL"; exit 1; fi
