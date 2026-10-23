#!/bin/bash
# One-shot IDE-CONTRACT happy paths on qemu-ide stubs — no real board.
# Covers: host Ver gate, tconn :8710, shell+__RC, file send/recv, fport add/ls/rm,
#         /data/ohjs + marker clean, negative :18710 (start-only).
# Ships in board package as verify-ide-contract-oneshot.sh (see package tools/).
#
# Usage:
#   ./verify-ide-contract-oneshot.sh
#   SKIP_START=1 ./verify-ide-contract-oneshot.sh   # assume run-qemu already up
#
# Exit 0 = all PASS. Log: lite/test/qemu-ide-contract-oneshot.log
set -u
D=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
PORT_ROOT=${PORT:-/workspace/hdcd-port}
HDC=${HDC:-$PORT_ROOT/hdc-host}
DEV_PORT=${HDCD_PORT:-8710}
WRONG_PORT=${WRONG_PORT:-18710}
export OHOS_HDC_SERVER_PORT=${OHOS_HDC_SERVER_PORT:-8711}
H="$HDC -s 127.0.0.1:$OHOS_HDC_SERVER_PORT"
T="-t 127.0.0.1:$DEV_PORT"
OUT=${OUT_LOG:-$PORT_ROOT/hdc/lite/test/qemu-ide-contract-oneshot.log}
R=0
BUNDLE=com.example.oneshot
MARKER=/data/ohjs/debug.$BUNDLE

mkdir -p "$(dirname "$OUT")"
exec > >(tee "$OUT") 2>&1

pass(){ echo "[PASS] $*"; }
fail(){ echo "[FAIL] $*"; R=1; }

echo "==== verify-ide-contract-oneshot $(date '+%Y-%m-%d %H:%M:%S %z') ===="
echo "See lite/docs/IDE-CONTRACT.md — host-only qemu stubs (aa/bm limits in qemu-ide/README.md)"

# Ensure start mode (not jsdebug)
if [ "${SKIP_START:-0}" != 1 ]; then
  if ! "$D/run-qemu-hdcd.sh" status 2>/dev/null | grep -q running; then
    "$D/run-qemu-hdcd.sh" start || { echo "cannot start qemu hdcd"; exit 2; }
  fi
fi
"$D/run-qemu-hdcd.sh" jsdebug stop >/dev/null 2>&1 || true
$H start >/dev/null 2>&1 || true
sleep 0.3

# --- 0) host version (contract companion) ---
GATE=$D/../../tools/board/check-host-hdc-ver.sh
if [ -x "$GATE" ]; then
  if HDC="$HDC" "$GATE"; then pass "hdc -v Ver 3.2.0c (gate)"; else fail "hdc Ver gate (see hints above)"; fi
else
  vo=$($HDC -v 2>&1 || true)
  echo "$vo" | grep -qE 'Ver:\s*3\.2\.0c' && pass "hdc -v Ver 3.2.0c" || fail "hdc -v ($vo)"
fi

# --- 1) tconn correct / wrong ---
o=$($H tconn 127.0.0.1:$DEV_PORT 2>&1 || true)
echo "$o" | grep -qiE 'Connect OK|already|connected|repeat' && pass "tconn :$DEV_PORT" || fail "tconn :$DEV_PORT ($o)"
wo=$($H tconn 127.0.0.1:$WRONG_PORT 2>&1 || true)
if echo "$wo" | grep -qiE 'Connect OK|already connected'; then
  fail "NEGATIVE: tconn :$WRONG_PORT unexpectedly OK"
else
  pass "NEGATIVE: tconn :$WRONG_PORT fails (start-only)"
fi

# --- 2) shell + __RC ---
so=$($H $T shell 'echo ONESHOT_OK; echo __RC=$?' 2>&1 || true)
echo "$so" | grep -q ONESHOT_OK && echo "$so" | grep -q '__RC=0' && pass "shell + __RC" || fail "shell ($so)"

# --- 3) paths ---
po=$($H $T shell 'mkdir -p /data/ohjs /tmp/ohjs; test -d /data/ohjs && test -d /tmp/ohjs && echo PATHS_OK; echo __RC=$?' 2>&1 || true)
echo "$po" | grep -q PATHS_OK && pass "paths /data/ohjs /tmp/ohjs" || fail "paths ($po)"

# --- 4) file send / recv ---
W=$(mktemp -d /tmp/ide-oneshot-XXXXXX)
echo 'oneshot-payload' > "$W/a.txt"
local_sha=$(sha256sum "$W/a.txt" | awk '{print $1}')
fo=$($H $T file send "$W/a.txt" /tmp/ohjs/oneshot.txt 2>&1 || true)
echo "$fo" | grep -qi 'FileTransfer finish' && pass "file send" || fail "file send ($fo)"
$H $T file recv /tmp/ohjs/oneshot.txt "$W/b.txt" >/dev/null 2>&1 || true
if [ -f "$W/b.txt" ] && [ "$(sha256sum "$W/b.txt" | awk '{print $1}')" = "$local_sha" ]; then
  pass "file recv sha match"
else
  fail "file recv/sha"
fi
rm -rf "$W"

# --- 5) fport add / ls / rm (loopback-style; device side may be unused) ---
# Use high host port; device tcp:19099 need not listen for fport bookkeeping
fp=$($H $T fport tcp:19099 tcp:19099 2>&1 || true)
echo "fport add: $fp"
echo "$fp" | grep -qiE 'OK|Forwardport' && pass "fport add" || fail "fport add ($fp)"
ls=$($H $T fport ls 2>&1 || true)
echo "$ls" | grep -q 'tcp:19099' && pass "fport ls" || fail "fport ls ($ls)"
rmo=$($H $T fport rm tcp:19099 tcp:19099 2>&1 || true)
echo "fport rm: $rmo"
# rm may print OK or empty — accept if ls no longer shows rule
ls2=$($H $T fport ls 2>&1 || true)
echo "$ls2" | grep -q 'tcp:19099' && fail "fport rm leftover" || pass "fport rm"

# --- 6) marker plant + clean deploy path ---
$H $T shell "mkdir -p /data/ohjs && touch $MARKER" >/dev/null 2>&1 || true
left=$($H $T shell "ls $MARKER 2>/dev/null; echo __RC=\$?" 2>&1 || true)
echo "$left" | grep -q "debug.$BUNDLE" && pass "marker create" || fail "marker create"
$H $T shell 'rm -f /data/ohjs/debug.*' >/dev/null 2>&1 || true
after=$($H $T shell 'ls /data/ohjs/debug.* 2>/dev/null || echo NONE' 2>&1 || true)
echo "$after" | grep -q NONE && pass "marker cleared (clean deploy)" || fail "marker leftover ($after)"

# --- 7) optional: delegate to verify-contract for full regression ---
if [ "${SKIP_VERIFY_CONTRACT:-0}" != 1 ]; then
  if "$D/verify-contract.sh"; then
    pass "verify-contract (nested)"
  else
    fail "verify-contract (nested)"
  fi
fi

echo "RESULT=$R log=$OUT"
echo "One-shot entry: lite/test/qemu-ide/verify-ide-contract-oneshot.sh (board package: tools/ or package root)."
exit $R
