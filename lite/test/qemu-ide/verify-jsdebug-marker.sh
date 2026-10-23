#!/bin/bash
# Verify IDE marker path /data/ohjs/debug.<bundle> gates wait-for-debugger in qemu jsdebug.
# Flow: create marker → start harness → listener + client e2e → delete marker → restart must NOT block.
# Logs: lite/test/qemu-jsdebug-marker.log (and /tmp/ohjs-fakeroot/run/jerry.log).
set -u
D=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
ROOT=$(cd "$D/../../.." && pwd)   # hdc repo root when script is lite/test/qemu-ide/
# Prefer workspace layout
PORT_ROOT=${PORT:-/workspace/hdcd-port}
HB=${HARNESS:-$PORT_ROOT/b/acelite-la64/acedbg-harness}
E2E=${E2E:-/workspace/ohos-lite-js-ide/packages/jerry-debug-client/test/e2e/qemu-jsdebug.e2e.mjs}
NS=${NS:-ohjsdbg}
LOG=/tmp/ohjs-fakeroot/run/jerry.log
BUNDLE=com.example.sample
MARKER=/data/ohjs/debug.$BUNDLE
OUT=${OUT_LOG:-$PORT_ROOT/hdc/lite/test/qemu-jsdebug-marker.log}
R=0
pass(){ echo "[PASS] $*"; }; fail(){ echo "[FAIL] $*"; R=1; }

mkdir -p "$(dirname "$OUT")"
exec > >(tee "$OUT") 2>&1

[ -x "$HB" ] || { echo "missing harness $HB"; exit 2; }
[ -f "$E2E" ] || { echo "missing e2e $E2E"; exit 2; }

# Ensure /data/ohjs exists (run-qemu also does this)
if [ ! -d /data/ohjs ]; then
  sudo mkdir -p /data/ohjs && sudo chown "$(id -un):$(id -gn)" /data/ohjs
fi
mkdir -p /data/ohjs

export JERRY_BIN=$HB
# Default FLAG_DIR is /data/ohjs inside the harness — do NOT set ACE_DEBUGGER_FLAG_DIR.
export JERRY_ARGS="--bundle $BUNDLE"
# Clear env overrides that would force wait
unset ACE_DEBUGGER_WAIT ACE_DEBUGGER_BIND ACE_DEBUGGER_PORT ACE_DEBUGGER_FLAG_DIR || true

listen5001(){ sudo ip netns exec $NS ss -Hltn 'sport = :5001' 2>/dev/null | awk '{print $4}'; }
up(){ "$D/run-qemu-hdcd.sh" jsdebug start >/dev/null || { fail "jsdebug start"; return 1; }; sleep "${1:-3}"; }
down(){ "$D/run-qemu-hdcd.sh" jsdebug stop >/dev/null; }

echo "==== verify-jsdebug-marker (/data/ohjs/debug.<bundle>) ===="
echo "harness=$HB marker=$MARKER log=$OUT"

echo "== A: marker present → wait + client e2e via fport"
rm -f /data/ohjs/debug.*
: > "$MARKER"
ls -la "$MARKER"
up 3
l=$(listen5001)
grep -q 'wait=1' "$LOG" && pass "gate on (marker)" || fail "gate on (see $LOG)"
[ "$l" = "127.0.0.1:5001" ] && pass "listener $l" || fail "listener '$l'"
# Client e2e (starts its own jsdebug unless SKIP); use SKIP and keep our env
down
: > "$MARKER"
if [ ! -f /workspace/ohos-lite-js-ide/packages/jerry-debug-client/out/index.js ]; then
  fail "jerry-debug-client not built (out/index.js missing)"
else
  env JERRY_BIN="$HB" JERRY_ARGS="--bundle $BUNDLE"     RUN_QEMU_HDCD="$D/run-qemu-hdcd.sh"     OHOS_HDC_SERVER_PORT="${OHOS_HDC_SERVER_PORT:-8711}"     HOST_PORT="${HOST_PORT:-18710}"     node "$E2E" > /tmp/jsdebug-marker-e2e.log 2>&1     && pass "jerry-debug-client e2e with marker"     || fail "e2e (see /tmp/jsdebug-marker-e2e.log)"
  grep -E '^\[(PASS|FAIL)\]' /tmp/jsdebug-marker-e2e.log | sed 's/^/    /' || true
fi
down

echo "== B: marker deleted → must NOT block"
rm -f "$MARKER" /data/ohjs/debug.*
up 4
l=$(listen5001)
grep -q 'wait=0' "$LOG" && pass "gate off without marker" || fail "gate off"
[ -z "$l" ] && pass "no :5001 listener" || fail "listener still present: $l"
grep -q 'done counter=33' "$LOG" && pass "app completed without wait" || fail "completion"
down

echo "== C: recreate marker via hdc shell (IDE path)"
# Shell through the jsdebug netns hdcd (bridged on HOST_PORT). Do not kill the host
# hdc server used by G2 on :8710 — use a dedicated server port if busy.
H=${HDC:-/workspace/hdcd-port/hdc-host}
SP=${OHOS_HDC_SERVER_PORT:-8711}
TARGET=${JSDEBUG_TARGET:-${HOST_PORT:-10.200.1.2:8710}}
# Prefer veth address; HOST_PORT may be "ip:port" or legacy localhost alias port
export OHOS_HDC_SERVER_PORT=$SP
rm -f /data/ohjs/debug.*
up 3
# wait for bridge
ok_tconn=0
for i in 1 2 3 4 5 6 7 8; do
  tconn=$($H -s 127.0.0.1:$SP tconn "$TARGET" 2>&1 || true)
  echo "tconn try $i: $tconn"
  echo "$tconn" | grep -qiE 'Connect OK|already' && { ok_tconn=1; break; }
  sleep 0.5
done
[ "$ok_tconn" = 1 ] && pass "hdc tconn jsdebug" || fail "hdc tconn jsdebug bridge"
$H -s 127.0.0.1:$SP -t "$TARGET" shell "mkdir -p /data/ohjs && touch /data/ohjs/debug.$BUNDLE; ls -la /data/ohjs/debug.$BUNDLE; echo __RC=\$?" 2>&1 | tee /tmp/marker-shell.txt
grep -q "debug.$BUNDLE" /tmp/marker-shell.txt && [ -f "$MARKER" ] && pass "hdc shell created marker" || fail "hdc shell marker"
down
# Restart with marker on disk (no FLAG_DIR / WAIT env) — proves default /data/ohjs path
up 3
l=$(listen5001)
grep -q 'wait=1' "$LOG" && [ "$l" = "127.0.0.1:5001" ] && pass "marker from hdc shell gates wait" || fail "hdc-shell marker gate ($l)"
down
rm -f /data/ohjs/debug.*
# Restore G2 tconn on :8710 without disrupting a long-lived server more than needed
$H -s 127.0.0.1:$SP tconn 127.0.0.1:8710 >/dev/null 2>&1 || true

echo "RESULT=$R log=$OUT"
exit $R
