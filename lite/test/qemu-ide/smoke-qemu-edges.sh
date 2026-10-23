#!/bin/bash
# qemu-ide edge cases on stubs (no board): large file, reconnect burst, concurrent sessions.
# Complements smoke-stability.sh. Log: lite/test/qemu-ide-edges.log
#
# Env: LARGE_MB (default 32), N_RECONN (10), N_CONCUR (6), HDC, HDCD_PORT, OHOS_HDC_SERVER_PORT
set -u
D=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
PORT_ROOT=${PORT:-/workspace/hdcd-port}
HDC=${HDC:-$PORT_ROOT/hdc-host}
DEV_PORT=${HDCD_PORT:-8710}
export OHOS_HDC_SERVER_PORT=${OHOS_HDC_SERVER_PORT:-8711}
H="$HDC -s 127.0.0.1:$OHOS_HDC_SERVER_PORT"
T="-t 127.0.0.1:$DEV_PORT"
OUT=${OUT_LOG:-$PORT_ROOT/hdc/lite/test/qemu-ide-edges.log}
R=0
LARGE_MB=${LARGE_MB:-32}
N_RECONN=${N_RECONN:-10}
N_CONCUR=${N_CONCUR:-6}

mkdir -p "$(dirname "$OUT")"
exec > >(tee "$OUT") 2>&1
pass(){ echo "[PASS] $*"; }; fail(){ echo "[FAIL] $*"; R=1; }

echo "==== smoke-qemu-edges $(date '+%Y-%m-%d %H:%M:%S %z') ===="

if ! "$D/run-qemu-hdcd.sh" status | grep -q running; then
  "$D/run-qemu-hdcd.sh" start || exit 2
fi
"$D/run-qemu-hdcd.sh" jsdebug stop >/dev/null 2>&1 || true
$H start >/dev/null 2>&1 || true
$H tconn 127.0.0.1:$DEV_PORT >/dev/null 2>&1 || true

shell_ok() {
  local o
  o=$($H $T shell 'echo EDGE_OK; echo __RC=$?' 2>&1 || true)
  echo "$o" | grep -q EDGE_OK && echo "$o" | grep -q '__RC=0'
}

# --- A) large file send/recv ---
echo "== A) large file ${LARGE_MB} MiB send/recv"
W=$(mktemp -d /tmp/edge-large-XXXXXX)
f="$W/big.bin"
dd if=/dev/urandom of="$f" bs=1M count="$LARGE_MB" status=none 2>/dev/null || \
  dd if=/dev/zero of="$f" bs=1M count="$LARGE_MB" status=none
lsha=$(sha256sum "$f" | awk '{print $1}')
$H $T shell 'mkdir -p /tmp/ohjs' >/dev/null 2>&1 || true
o=$($H $T file send "$f" /tmp/ohjs/edge-big.bin 2>&1 || true)
echo "send: $(echo "$o" | tr '\n' ' ' | tail -c 160)"
if echo "$o" | grep -qi 'FileTransfer finish'; then
  $H $T file recv /tmp/ohjs/edge-big.bin "$W/back.bin" >/dev/null 2>&1 || true
  rsha=$(sha256sum "$W/back.bin" 2>/dev/null | awk '{print $1}')
  if [ "$lsha" = "$rsha" ]; then
    pass "large file ${LARGE_MB}MiB sha match"
  else
    fail "large file sha mismatch"
  fi
else
  fail "large file send (no finish)"
fi
rm -rf "$W"

# --- B) disconnect/reconnect burst ---
echo "== B) reconnect ×$N_RECONN"
for i in $(seq 1 "$N_RECONN"); do
  $H tconn 127.0.0.1:$DEV_PORT -remove >/dev/null 2>&1 || true
  sleep 0.2
  o=$($H tconn 127.0.0.1:$DEV_PORT 2>&1 || true)
  if echo "$o" | grep -qiE 'Connect OK|already|connected|repeat' && shell_ok; then
    pass "reconnect #$i"
  else
    sleep 0.4
    o=$($H tconn 127.0.0.1:$DEV_PORT 2>&1 || true)
    if shell_ok; then pass "reconnect #$i (retry)"; else fail "reconnect #$i"; fi
  fi
done

# --- C) concurrent sessions (parallel shell + parallel tiny file send) ---
echo "== C) concurrent sessions ×$N_CONCUR (shell + file)"
PDIR=$(mktemp -d /tmp/edge-concur-XXXXXX)
pids=()
for i in $(seq 1 "$N_CONCUR"); do
  (
    ok=1
    o=$($H $T shell "echo CONCUR_$i; echo __RC=\$?" 2>&1 || true)
    echo "$o" | grep -q "CONCUR_$i" && echo "$o" | grep -q '__RC=0' || ok=0
    tf="$PDIR/t-$i.txt"
    echo "payload-$i" > "$tf"
    fo=$($H $T file send "$tf" "/tmp/ohjs/edge-c-$i.txt" 2>&1 || true)
    echo "$fo" | grep -qi 'FileTransfer finish' || ok=0
    if [ "$ok" = 1 ]; then echo OK > "$PDIR/$i"; else echo "$o | $fo" > "$PDIR/$i.err"; echo FAIL > "$PDIR/$i"; fi
  ) &
  pids+=($!)
done
for p in "${pids[@]}"; do wait "$p" || true; done
cok=0
for i in $(seq 1 "$N_CONCUR"); do
  if [ -f "$PDIR/$i" ] && grep -q OK "$PDIR/$i"; then cok=$((cok+1)); else fail "concurrent #$i"; fi
done
[ "$cok" = "$N_CONCUR" ] && pass "concurrent $cok/$N_CONCUR" || fail "concurrent only $cok/$N_CONCUR"
rm -rf "$PDIR"

shell_ok && pass "post-edge health" || fail "post-edge health"
echo "RESULT=$R log=$OUT"
exit $R
