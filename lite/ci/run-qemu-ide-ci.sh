#!/bin/bash
# CI entry: soak-ide-contract (≥20) + smoke-qemu-edges when qemu-ide env is available.
# Skip (exit 0) if qemu-loongarch64 / HDCD_BIN / host hdc missing — do not fail the job.
# When available, both must PASS (exit non-zero on failure).
#
# Env:
#   HDCD_BIN   loongarch64 hdcd (default: search common paths / release extract)
#   HDC / PORT host hdc client
#   SOAK_N / N (default 20), LARGE_MB, N_RECONN, N_CONCUR
#   FORCE_RUN=1  fail instead of skip when env missing
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
QEMU_IDE=$ROOT/lite/test/qemu-ide
PORT_ROOT=${PORT:-$(cd "$ROOT/.." 2>/dev/null && pwd)}
# Prefer sibling hdcd-port layout, then env, then package-style paths
HDCD_BIN=${HDCD_BIN:-}
HDC=${HDC:-}

find_hdcd() {
  local c
  for c in \
    "$HDCD_BIN" \
    "$PORT_ROOT/b/out/hdcd.stripped" \
    "$PORT_ROOT/handoff-2026-10-29/hdcd.stripped" \
    "$ROOT/../handoff-2026-10-29/hdcd.stripped" \
    /tmp/ohjs-board/hdcd.stripped \
    "$PWD/hdcd.stripped"
  do
    [ -n "$c" ] && [ -x "$c" ] && { echo "$c"; return 0; }
    [ -n "$c" ] && [ -f "$c" ] && chmod +x "$c" 2>/dev/null && [ -x "$c" ] && { echo "$c"; return 0; }
  done
  return 1
}

find_hdc() {
  local c
  for c in \
    "$HDC" \
    "$PORT_ROOT/hdc-host" \
    "$PORT_ROOT/handoff-2026-10-29/host/hdc-linux-x86_64" \
    "$ROOT/../handoff-2026-10-29/host/hdc-linux-x86_64" \
    /tmp/ohjs-board/host/hdc-linux-x86_64 \
    "$(command -v hdc 2>/dev/null || true)"
  do
    [ -n "$c" ] && [ -x "$c" ] && { echo "$c"; return 0; }
    [ -n "$c" ] && [ -f "$c" ] && chmod +x "$c" 2>/dev/null && [ -x "$c" ] && { echo "$c"; return 0; }
  done
  return 1
}

skip() {
  echo "::notice::qemu-ide CI skipped — $*"
  echo "SKIP reason: $*"
  if [ "${FORCE_RUN:-0}" = 1 ]; then
    echo "FORCE_RUN=1 — treating skip as failure"
    exit 2
  fi
  exit 0
}

echo "==== run-qemu-ide-ci $(date '+%Y-%m-%d %H:%M:%S %z') ===="

command -v qemu-loongarch64 >/dev/null 2>&1 || skip "qemu-loongarch64 not on PATH (install qemu-user-static)"

HDCD_BIN=$(find_hdcd) || skip "no loongarch64 hdcd.stripped (set HDCD_BIN or extract board package)"
HDC=$(find_hdc) || skip "no host hdc (set HDC or use package host/hdc-linux-x86_64)"

export HDCD_BIN HDC PORT="${PORT:-$PORT_ROOT}"
export OHOS_HDC_SERVER_PORT=${OHOS_HDC_SERVER_PORT:-8711}
export N=${N:-${SOAK_N:-20}}
export LARGE_MB=${LARGE_MB:-16}
export N_RECONN=${N_RECONN:-8}
export N_CONCUR=${N_CONCUR:-4}

echo "HDCD_BIN=$HDCD_BIN"
echo "HDC=$HDC"
"$HDC" -v 2>&1 | head -3 || true

# Ensure /data/ohjs writable (qemu-user shares host FS)
if [ ! -d /data/ohjs ] || [ ! -w /data/ohjs ]; then
  sudo mkdir -p /data/ohjs && sudo chown "$(id -un):$(id -gn)" /data/ohjs || \
    skip "/data/ohjs not writable (need sudo on runner)"
fi

# Start G2 once
"$QEMU_IDE/run-qemu-hdcd.sh" stop >/dev/null 2>&1 || true
"$QEMU_IDE/run-qemu-hdcd.sh" jsdebug stop >/dev/null 2>&1 || true
HDCD_BIN="$HDCD_BIN" "$QEMU_IDE/run-qemu-hdcd.sh" start || {
  echo "run-qemu-hdcd.sh start failed"
  exit 1
}

export SKIP_START=1
R=0
echo "== smoke-qemu-edges =="
if ! LARGE_MB="$LARGE_MB" N_RECONN="$N_RECONN" N_CONCUR="$N_CONCUR" \
    HDC="$HDC" HDCD_BIN="$HDCD_BIN" "$QEMU_IDE/smoke-qemu-edges.sh"; then
  echo "[FAIL] smoke-qemu-edges"
  R=1
else
  echo "[PASS] smoke-qemu-edges"
fi

echo "== soak-ide-contract N=$N =="
if ! N="$N" HDC="$HDC" HDCD_BIN="$HDCD_BIN" SKIP_START=1 \
    "$QEMU_IDE/soak-ide-contract.sh"; then
  echo "[FAIL] soak-ide-contract"
  R=1
else
  echo "[PASS] soak-ide-contract"
fi

"$QEMU_IDE/run-qemu-hdcd.sh" stop >/dev/null 2>&1 || true
echo "RESULT=$R"
exit $R
