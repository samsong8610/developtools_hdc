#!/bin/bash
# Offline ABI / debug-libs readiness smoke (no board HW).
# Chains: smoke-abi-compare → smoke-pack-debug-libs → smoke-from-board-results.
# Requires --ours / PORT/b/acelite-la64 built. Exit 0 = pack pipeline ready for real board-results.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PORT=${PORT:-/workspace/hdcd-port}
OURS=${OURS:-$PORT/b/acelite-la64}
export PORT OURS
R=0

echo "==== smoke-abi-offline $(date '+%Y-%m-%d %H:%M:%S %z') ===="
echo "OURS=$OURS"
if [ ! -f "$OURS/libace_lite.so" ]; then
  echo "[FAIL] missing $OURS/libace_lite.so — build acelite-la64 (or set OURS=) before offline smoke"
  echo "RESULT=2"
  exit 2
fi

run(){
  local label=$1; shift
  echo ""
  echo "---- $label ----"
  set +e
  "$@"
  local rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    echo "[PASS] $label"
  else
    echo "[FAIL] $label (rc=$rc)"
    R=1
  fi
}

run "smoke-abi-compare" bash "$HERE/smoke-abi-compare.sh"
run "smoke-pack-debug-libs" bash "$HERE/smoke-pack-debug-libs.sh"
run "smoke-from-board-results" bash "$HERE/smoke-from-board-results.sh"

echo ""
if [ "$R" -eq 0 ]; then
  echo "Offline ABI pipeline ready: when board-results-*.zip arrives → ./from-board-results.sh <zip>"
fi
echo "RESULT=$R"
exit $R
