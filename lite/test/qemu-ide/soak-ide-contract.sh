#!/bin/bash
# Soak: run verify-ide-contract-oneshot.sh N times (default 20), fail-fast.
# No board. Logs under lite/test/qemu-ide-soak/iter-NNN.log + summary.
#
# Usage:
#   ./soak-ide-contract.sh              # N=20
#   N=30 ./soak-ide-contract.sh
#   N=5 SKIP_START=0 ./soak-ide-contract.sh
#
# CI/doc: set SOAK_N or N; SKIP_CONTRACT nested inside oneshot still applies via env.
# Exit 0 = all iterations PASS; non-zero = first failure (logs preserved).
# Failure archive (fail-fast):
#   $OUT_DIR/failures/fail-iter-NNN/   — copy of iter log + SUMMARY snippet + REPRO.txt
#   Convention also documented in lite/docs/SOAK-FAILURE-ARCHIVE.md
#   CI uploads lite/test/qemu-ide-soak/ (includes failures/).
set -u
D=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
PORT_ROOT=${PORT:-/workspace/hdcd-port}
N=${N:-${SOAK_N:-20}}
OUT_DIR=${OUT_DIR:-$PORT_ROOT/hdc/lite/test/qemu-ide-soak}
SUMMARY=$OUT_DIR/SUMMARY.txt

mkdir -p "$OUT_DIR"
: > "$SUMMARY"

echo "==== soak-ide-contract N=$N $(date '+%Y-%m-%d %H:%M:%S %z') ====" | tee -a "$SUMMARY"

# Start once; iterations use SKIP_START=1
if [ "${SKIP_START:-0}" != 1 ]; then
  if ! "$D/run-qemu-hdcd.sh" status 2>/dev/null | grep -q running; then
    "$D/run-qemu-hdcd.sh" start || { echo "cannot start qemu hdcd" | tee -a "$SUMMARY"; exit 2; }
  fi
fi
"$D/run-qemu-hdcd.sh" jsdebug stop >/dev/null 2>&1 || true
OHOS_HDC_SERVER_PORT=${OHOS_HDC_SERVER_PORT:-8711} \
  "${HDC:-$PORT_ROOT/hdc-host}" -s 127.0.0.1:${OHOS_HDC_SERVER_PORT:-8711} start >/dev/null 2>&1 || true

export SKIP_START=1
# Nested verify-contract every iter is heavy; keep it (contract soak) unless SOAK_SKIP_NESTED=1
if [ "${SOAK_SKIP_NESTED:-0}" = 1 ]; then
  export SKIP_VERIFY_CONTRACT=1
fi

ok=0
for i in $(seq 1 "$N"); do
  iter=$(printf '%03d' "$i")
  log="$OUT_DIR/iter-$iter.log"
  echo "---- soak iter $i/$N → $log ----" | tee -a "$SUMMARY"
  if OUT_LOG="$log" "$D/verify-ide-contract-oneshot.sh" >>"$log" 2>&1; then
    echo "[PASS] iter $i/$N" | tee -a "$SUMMARY"
    ok=$((ok + 1))
  else
    echo "[FAIL] iter $i/$N — fail-fast; see $log" | tee -a "$SUMMARY"
    echo "RESULT=1 passed=$ok/$N failed_at=$i log=$log" | tee -a "$SUMMARY"
    # Minimal failure archive for CI / local drop
    FAIL_DIR=$OUT_DIR/failures/fail-iter-$iter
    mkdir -p "$FAIL_DIR"
    cp -a "$log" "$FAIL_DIR/iter.log" 2>/dev/null || true
    cp -a "$SUMMARY" "$FAIL_DIR/SUMMARY.txt" 2>/dev/null || true
    # Oneshoot nested logs if present
    for extra in \
      "$PORT_ROOT/hdc/lite/test/qemu-ide-contract-oneshot.log" \
      "$PORT_ROOT/hdc/lite/test/qemu-ide-contract.log"
    do
      [ -f "$extra" ] && cp -a "$extra" "$FAIL_DIR/" || true
    done
    {
      echo "# Soak failure repro — drop this directory into bug reports"
      echo "failed_at_iter=$i"
      echo "N=$N"
      echo "log=iter.log"
      echo "OUT_DIR=$OUT_DIR"
      echo "FAIL_DIR=$FAIL_DIR"
      echo "HDCD_BIN=${HDCD_BIN:-}"
      echo "HDC=${HDC:-$PORT_ROOT/hdc-host}"
      echo "OHOS_HDC_SERVER_PORT=${OHOS_HDC_SERVER_PORT:-8711}"
      echo "HDCD_PORT=${HDCD_PORT:-8710}"
      echo "SKIP_START=1"
      echo "SOAK_SKIP_NESTED=${SOAK_SKIP_NESTED:-0}"
      echo "date=$(date '+%Y-%m-%d %H:%M:%S %z')"
      echo "tip=$(git -C "$(dirname "$D")/../.." rev-parse --short=8 HEAD 2>/dev/null || echo unknown)"
      echo ""
      echo "## Minimal repro"
      echo "1. Ensure qemu-ide G2 up: lite/test/qemu-ide/run-qemu-hdcd.sh start"
      echo "2. export OHOS_HDC_SERVER_PORT=8711 HDC=... HDCD_BIN=..."
      echo "3. SKIP_START=1 OUT_LOG=/tmp/repro-oneshot.log lite/test/qemu-ide/verify-ide-contract-oneshot.sh"
      echo "4. Or re-run soak: N=1 SKIP_START=1 lite/test/qemu-ide/soak-ide-contract.sh"
      echo "5. Attach this FAIL_DIR (iter.log + REPRO.txt + SUMMARY.txt)"
    } > "$FAIL_DIR/REPRO.txt"
    echo "failure archive: $FAIL_DIR (see lite/docs/SOAK-FAILURE-ARCHIVE.md)" | tee -a "$SUMMARY"
    # Pointer at known drop path
    ln -sfn "failures/fail-iter-$iter" "$OUT_DIR/LAST_FAILURE" 2>/dev/null || true
    exit 1
  fi
done

echo "RESULT=0 passed=$ok/$N dir=$OUT_DIR" | tee -a "$SUMMARY"
exit 0
