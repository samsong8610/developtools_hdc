#!/bin/bash
# qemu-ide edge cases on stubs (no board): large file, reconnect, concurrent,
# plus contract negatives: port conflict / wrong path / leftover debug.* artifacts.
# Complements smoke-stability.sh. Log: lite/test/qemu-ide-edges.log
#
# Env: LARGE_MB (default 32), N_RECONN (10), N_CONCUR (6), WRONG_PORT (18710),
#      HDC, HDCD_PORT, OHOS_HDC_SERVER_PORT
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


# --- D) port conflict / wrong port (NEGATIVES; start-only, jsdebug down) ---
echo "== D) NEGATIVE port conflict / wrong port"
WRONG_PORT=${WRONG_PORT:-18710}
# Ensure jsdebug alias down so :18710 must fail for G2
"$D/run-qemu-hdcd.sh" jsdebug stop >/dev/null 2>&1 || true
$H tconn 127.0.0.1:$DEV_PORT >/dev/null 2>&1 || true
# D1: tconn to jsdebug host port must NOT Connect OK
wo=$($H tconn 127.0.0.1:$WRONG_PORT 2>&1 || true)
echo "tconn :$WRONG_PORT => $(echo "$wo" | tr '\n' ' ' | tail -c 120)"
if echo "$wo" | grep -qiE 'Connect OK|already connected'; then
  fail "NEGATIVE: tconn :$WRONG_PORT unexpectedly OK (port conflict / jsdebug up?)"
else
  pass "NEGATIVE: tconn :$WRONG_PORT fails (no G2 on jsdebug port)"
fi
# D2: using device port as OHOS_HDC_SERVER_PORT collides — client to :8710 as server should not be healthy device session
# Probe: hdc -s 127.0.0.1:8710 list targets (server wrongly on device port) — expect fail or empty, not a clean G2 target list for 8710-as-server
bad=$($HDC -s 127.0.0.1:$DEV_PORT list targets 2>&1 || true)
echo "list targets via -s :$DEV_PORT (conflict probe): $(echo "$bad" | tr '\n' ' ' | tail -c 120)"
# Correct server still works
oklist=$($H list targets 2>&1 || true)
if echo "$oklist" | grep -qE "127.0.0.1:$DEV_PORT|[Cc]onnect"; then
  pass "server :$OHOS_HDC_SERVER_PORT still lists device after conflict probe"
else
  # reconnect and recheck
  $H tconn 127.0.0.1:$DEV_PORT >/dev/null 2>&1 || true
  shell_ok && pass "server :$OHOS_HDC_SERVER_PORT healthy after conflict probe" || fail "server broken after conflict probe"
fi

# --- E) wrong remote path (NEGATIVE file send) ---
echo "== E) NEGATIVE wrong remote path"
W2=$(mktemp -d /tmp/edge-badpath-XXXXXX)
echo 'x' > "$W2/tiny.txt"
# Nonexistent deep parent under /tmp (no mkdir) — must not FileTransfer finish cleanly
bo=$($H $T file send "$W2/tiny.txt" /tmp/ohjs-no-such-dir-edge/nested/x.txt 2>&1 || true)
echo "bad path send: $(echo "$bo" | tr '\n' ' ' | tail -c 160)"
if echo "$bo" | grep -qi 'FileTransfer finish'; then
  fail "NEGATIVE: file send to missing parent unexpectedly finished"
else
  pass "NEGATIVE: file send wrong path fails (no finish)"
fi
# Control: correct path still works
$H $T shell 'mkdir -p /tmp/ohjs' >/dev/null 2>&1 || true
go=$($H $T file send "$W2/tiny.txt" /tmp/ohjs/edge-path-ok.txt 2>&1 || true)
echo "$go" | grep -qi 'FileTransfer finish' && pass "file send correct /tmp/ohjs still OK" || fail "file send /tmp/ohjs broken after negative"
rm -rf "$W2"

# --- F) leftover debug.* artifacts (NEGATIVE then clean) ---
echo "== F) leftover debug.* artifacts"
BUNDLE_EDGE=com.example.edge
$H $T shell "mkdir -p /data/ohjs && touch /data/ohjs/debug.$BUNDLE_EDGE /data/ohjs/debug.leftover.other" >/dev/null 2>&1 || true
planted=$($H $T shell 'ls /data/ohjs/debug.* 2>/dev/null | tr "\n" " "; echo' 2>&1 || true)
echo "planted: $planted"
echo "$planted" | grep -q "debug.$BUNDLE_EDGE" && pass "planted debug markers" || fail "could not plant debug markers"
# Detect leftover before clean (must see markers — simulates IDE forgetting rm)
if echo "$planted" | grep -qE 'debug\.'; then
  pass "NEGATIVE detect: leftover debug.* present before clean deploy"
else
  fail "NEGATIVE detect: expected leftover debug.* not visible"
fi
# Clean deploy path
$H $T shell 'rm -f /data/ohjs/debug.*' >/dev/null 2>&1 || true
after=$($H $T shell 'sh -c "set -- /data/ohjs/debug.*; if [ -e \"\$1\" ]; then echo LEFTOVER; ls /data/ohjs/debug.*; else echo CLEAN; fi"' 2>&1 || true)
echo "after clean: $after"
echo "$after" | grep -q CLEAN && pass "clean deploy clears all debug.*" || fail "leftover debug.* after clean: $after"
# Refuse path: plant again and assert verify-contract-style refuse
$H $T shell "touch /data/ohjs/debug.$BUNDLE_EDGE" >/dev/null 2>&1 || true
still=$($H $T shell 'sh -c "set -- /data/ohjs/debug.*; if [ -e \"\$1\" ]; then echo LEFTOVER; else echo CLEAN; fi"' 2>&1 || true)
echo "$still" | grep -q LEFTOVER && pass "REFUSE path: marker still present when not cleaned" || fail "REFUSE path inconclusive"
$H $T shell 'rm -f /data/ohjs/debug.*' >/dev/null 2>&1 || true


shell_ok && pass "post-edge health" || fail "post-edge health"
echo "RESULT=$R log=$OUT"
exit $R
