#!/bin/bash
# G4: JerryScript debugger (6.1-LTS, la64, JERRY_DEBUGGER=1) in netns, reached ONLY via hdcd fport.
set -u
D=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
HDC=${HDC:-/workspace/hdcd-port/hdc-host}; HP=${HOST_PORT:-18710}
# Plain jerry (not acedbg-harness). Clear leftover marker-test env that would skip wait-for-client.
unset JERRY_ARGS JERRY_ENV ACE_DEBUGGER_WAIT ACE_DEBUGGER_BIND ACE_DEBUGGER_PORT ACE_DEBUGGER_FLAG_DIR || true
export JERRY_BIN=${JERRY_BIN:-/workspace/hdcd-port/b/jerry-la64/bin/jerry}
CLIENT=${JERRY_CLIENT:-/workspace/oh61src/third_party_jerryscript/jerry-debugger/jerry_client.py}
# jerry_client.py of JerryScript 2.3 (6.1-LTS) is python2-only
PY2=${PY2:-$(command -v python2 || echo /workspace/py27/inst/bin/python2)}
export OHOS_HDC_SERVER_PORT=${OHOS_HDC_SERVER_PORT:-8711}
H="$HDC -s 127.0.0.1:$OHOS_HDC_SERVER_PORT"; T="-t 127.0.0.1:$HP"; R=0
pass(){ echo "[PASS] $*"; }; fail(){ echo "[FAIL] $*"; R=1; }
"$D/run-qemu-hdcd.sh" jsdebug start || exit 1
trap '$H $T fport rm tcp:19001 tcp:5001 >/dev/null 2>&1; $H kill >/dev/null 2>&1; "$D/run-qemu-hdcd.sh" jsdebug stop >/dev/null' EXIT
sleep 2
python3 - <<'P' && pass "host cannot reach :5001 directly (127.0.0.1)" || fail "5001 reachable on host"
import socket,sys
s=socket.socket(); s.settimeout(1)
sys.exit(0 if s.connect_ex(("127.0.0.1",5001))!=0 else 1)
P
o=$($H tconn 127.0.0.1:$HP 2>&1); echo "tconn: $o"; echo "$o" | grep -q 'Connect OK' && pass tconn || fail tconn
o=$($H $T fport tcp:19001 tcp:5001 2>&1); echo "fport: $o"; echo "$o" | grep -qi 'ok' && pass "fport tcp:19001 tcp:5001" || fail fport
$H $T fport ls
CMDS=$'b sample.js:3\nc\nbt\ne a+b\ne counter\ndelete all\nc\n'
o=$(printf '%s' "$CMDS" | timeout 60 "$PY2" "$CLIENT" --non-interactive localhost:19001 2>&1); echo "--- jerry_client:"; echo "$o"
echo "$o" | grep -q 'Breakpoint 1 at sample.js:3' && pass "breakpoint set" || fail "breakpoint set"
echo "$o" | grep -q 'Stopped at breakpoint:1' && pass "breakpoint hit" || fail "bp hit"
echo "$o" | grep -qE 'Frame 0: sample.js:3' && pass "backtrace" || fail backtrace
echo "$o" | grep -qx '10' && pass "eval a+b = 10" || fail "eval"
sleep 1; grep -q 'done counter=33' /tmp/ohjs-fakeroot/run/jerry.log && pass "script ran to completion (counter=33)" || fail "completion"
echo "--- jerry.log:"; cat /tmp/ohjs-fakeroot/run/jerry.log
echo "RESULT=$R"; exit $R
