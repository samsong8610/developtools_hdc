#!/bin/bash
# ACE lite debugger gate (ACE_LITE_DEBUGGER_GATE) in the jsdebug netns, using b/acelite-la64/acedbg-harness
# (same js_debugger_gate.h + jerryx_debugger_tcp_create_bind as libace_lite.so):
#  1 default off: no listener, script runs to completion without waiting
#  2 env ACE_DEBUGGER_WAIT=1: waits, listener is 127.0.0.1:5001 only, full debug session through hdc fport
#  3 flag file <dir>/debug.<bundle>: waits for that bundle only
#  4 ACE_DEBUGGER_BIND=0.0.0.0 override is honoured
set -u
D=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
HB=${HARNESS:-/workspace/hdcd-port/b/acelite-la64/acedbg-harness}
E2E=${E2E:-/workspace/ohos-lite-js-ide/packages/jerry-debug-client/test/e2e/qemu-jsdebug.e2e.mjs}
NS=${NS:-ohjsdbg}; LOG=/tmp/ohjs-fakeroot/run/jerry.log; R=0
pass(){ echo "[PASS] $*"; }; fail(){ echo "[FAIL] $*"; R=1; }
export JERRY_BIN=$HB JERRY_ARGS="--bundle com.example.sample"
listen5001(){ sudo ip netns exec $NS ss -Hltn 'sport = :5001' | awk '{print $4}'; }
up(){ JERRY_ENV="$1" "$D/run-qemu-hdcd.sh" jsdebug start >/dev/null || { fail "jsdebug start"; return 1; }; sleep "${2:-3}"; }
down(){ "$D/run-qemu-hdcd.sh" jsdebug stop >/dev/null; }

echo "== 1 default (gate off)"
up "" 4; l=$(listen5001)
grep -q 'wait=0 .*reason=default off' $LOG && pass "gate default off" || fail "gate default off"
[ -z "$l" ] && pass "no debugger listener" || fail "listener present: $l"
grep -q 'done counter=33' $LOG && pass "app ran to completion without waiting" || fail "completion"
down

echo "== 2 env ACE_DEBUGGER_WAIT=1 (+ client e2e through hdc fport)"
up "ACE_DEBUGGER_WAIT=1"; l=$(listen5001)
[ "$l" = "127.0.0.1:5001" ] && pass "listener bound to loopback only ($l)" || fail "listener '$l'"
grep -q 'done counter' $LOG && fail "did not wait" || pass "app is waiting for debugger"
down
JERRY_ENV="ACE_DEBUGGER_WAIT=1" node "$E2E" > /tmp/acedbg-e2e.log 2>&1 && pass "jerry-debug-client e2e via fport (loopback bind)" || fail "e2e (see /tmp/acedbg-e2e.log)"
grep -E '^\[(PASS|FAIL)\]' /tmp/acedbg-e2e.log | sed 's/^/    /'

echo "== 3 flag file"
mkdir -p /tmp/ohjs/flags; rm -f /tmp/ohjs/flags/*; : > /tmp/ohjs/flags/debug.com.example.sample
up "ACE_DEBUGGER_FLAG_DIR=/tmp/ohjs/flags"; l=$(listen5001)
grep -q 'wait=1 .*reason=flag file' $LOG && [ "$l" = "127.0.0.1:5001" ] && pass "flag file enables wait for its bundle" || fail "flag file ($l)"
down
JERRY_ARGS="--bundle com.other.app" up "ACE_DEBUGGER_FLAG_DIR=/tmp/ohjs/flags" 4; l=$(listen5001)
[ -z "$l" ] && grep -q 'done counter=33' $LOG && pass "other bundle not gated" || fail "other bundle ($l)"
down
printf 'port=5001\nbind=0.0.0.0\n' > /tmp/ohjs/flags/debug.com.example.sample

echo "== 4 bind override"
up "ACE_DEBUGGER_FLAG_DIR=/tmp/ohjs/flags"; l=$(listen5001)
[ "$l" = "0.0.0.0:5001" ] && pass "flag file bind=0.0.0.0 honoured" || fail "bind override '$l'"
down
up "ACE_DEBUGGER_WAIT=1 ACE_DEBUGGER_BIND=0.0.0.0"; l=$(listen5001)
[ "$l" = "0.0.0.0:5001" ] && pass "env ACE_DEBUGGER_BIND honoured" || fail "env bind '$l'"
down; rm -rf /tmp/ohjs/flags
echo "RESULT=$R"; exit $R
