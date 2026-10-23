#!/bin/bash
# One-shot lite docs / contract regression (no board, no qemu).
# Chains: schema validate + mapping↔JSON + BOARD-RECOVERY refs + soak LAST_FAILURE sample.
# Exit 0 = all green; RESULT=N aggregates failing steps.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
R=0
pass(){ echo "[PASS] $*"; }
fail(){ echo "[FAIL] $*"; R=1; }
run(){
  local label=$1; shift
  echo ""
  echo "==== $label ===="
  set +e
  "$@"
  local rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    pass "$label (rc=0)"
  else
    fail "$label (rc=$rc)"
  fi
}

echo "==== run-lite-docs-regression $(date '+%Y-%m-%d %H:%M:%S %z') ===="
echo "tip=$(git rev-parse --short=8 HEAD 2>/dev/null || echo unknown)"

run "validate-ide-error-codes" bash lite/ci/validate-ide-error-codes.sh
run "check-ide-error-codes-mapping" bash lite/ci/check-ide-error-codes-mapping.sh
run "check-board-recovery-refs" bash lite/tools/board/check-board-recovery-refs.sh

echo ""
echo "==== soak LAST_FAILURE sample existence ===="
SAMPLE=lite/docs/examples/soak-last-failure
if [ ! -d "$SAMPLE" ]; then
  fail "missing $SAMPLE"
elif [ ! -L "$SAMPLE/LAST_FAILURE" ]; then
  fail "$SAMPLE/LAST_FAILURE not a symlink"
else
  target=$(readlink "$SAMPLE/LAST_FAILURE")
  case "$target" in
    failures/fail-iter-*|*/failures/fail-iter-*) pass "LAST_FAILURE → $target" ;;
    *) fail "LAST_FAILURE target unexpected: $target" ;;
  esac
  dest="$SAMPLE/$target"
  # resolve relative
  if [ ! -d "$dest" ]; then
    dest="$SAMPLE/$(basename "$target")"
    [ -d "$SAMPLE/failures/$(basename "$target")" ] && dest="$SAMPLE/failures/$(basename "$target")"
  fi
  # Prefer joining SAMPLE + relative target
  dest="$SAMPLE/$target"
  if [ -d "$dest" ]; then
    for f in REPRO.txt iter.log SUMMARY.txt; do
      [ -f "$dest/$f" ] && pass "sample has $f" || fail "sample missing $f under $dest"
    done
  else
    fail "LAST_FAILURE dest missing: $dest"
  fi
  [ -f "$SAMPLE/SUMMARY.txt" ] && pass "sample root SUMMARY.txt" || fail "sample root SUMMARY.txt missing"
  [ -f "$SAMPLE/README.md" ] && pass "sample README.md" || fail "sample README.md missing"
fi

# Pin-sync checklist present (doc only; JSON stays 1.0.0 for now)
if [ -f lite/docs/IDE-ERROR-CODES-PIN-SYNC.md ]; then
  pass "IDE-ERROR-CODES-PIN-SYNC.md present"
else
  fail "missing lite/docs/IDE-ERROR-CODES-PIN-SYNC.md"
fi

echo ""
echo "RESULT=$R"
exit $R
