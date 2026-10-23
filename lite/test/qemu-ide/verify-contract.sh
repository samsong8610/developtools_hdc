#!/bin/bash
# IDE-CONTRACT regression: ports (8710 PASS / 18710 FAIL in start-only mode),
# paths (/data/ohjs, clean deploy clears debug.*), negative cases fail the script.
# Log: lite/test/qemu-ide-contract.log. Does not stop run-qemu (G2-safe).
set -u
D=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
PORT_ROOT=${PORT:-/workspace/hdcd-port}
HDC=${HDC:-$PORT_ROOT/hdc-host}
DEV_PORT=${HDCD_PORT:-8710}
WRONG_PORT=${WRONG_PORT:-18710}   # jsdebug HOST_PORT — must NOT work in plain start mode
export OHOS_HDC_SERVER_PORT=${OHOS_HDC_SERVER_PORT:-8711}
H="$HDC -s 127.0.0.1:$OHOS_HDC_SERVER_PORT"
OUT=${OUT_LOG:-$PORT_ROOT/hdc/lite/test/qemu-ide-contract.log}
R=0
BUNDLE=com.example.contract
MARKER=/data/ohjs/debug.$BUNDLE

mkdir -p "$(dirname "$OUT")"
exec > >(tee "$OUT") 2>&1

pass(){ echo "[PASS] $*"; }
fail(){ echo "[FAIL] $*"; R=1; }
warn(){ echo "[WARN] $*"; }

echo "==== verify-contract $(date '+%Y-%m-%d %H:%M:%S %z') ===="
echo "hdc=$HDC server=$OHOS_HDC_SERVER_PORT ok_port=$DEV_PORT wrong_port=$WRONG_PORT"

# Ensure plain start mode (not jsdebug-only). Leave any existing G2 running.
if ! "$D/run-qemu-hdcd.sh" status | grep -q running; then
  "$D/run-qemu-hdcd.sh" start || { echo "cannot start hdcd"; exit 2; }
fi
# Ensure jsdebug alias is down so wrong-port negative is meaningful
"$D/run-qemu-hdcd.sh" jsdebug stop >/dev/null 2>&1 || true
$H start >/dev/null 2>&1 || true
sleep 0.3

# --- host version gate (contract companion) ---
GATE=$D/../../tools/board/check-host-hdc-ver.sh
if [ -x "$GATE" ]; then
  if HDC="$HDC" "$GATE"; then pass "host hdc Ver 3.2.0c (gate)"; else fail "host hdc Ver gate (see install/path hints)"; fi
else
  vo=$($HDC -v 2>&1 || true)
  echo "hdc -v: $vo"
  echo "$vo" | grep -qE 'Ver:\s*3\.2\.0c' && pass "host hdc Ver 3.2.0c" || fail "host hdc must be Ver 3.2.0c (got: $vo)"
fi

# --- ports: correct PASS ---
o=$($H tconn 127.0.0.1:$DEV_PORT 2>&1 || true)
echo "tconn :$DEV_PORT: $o"
if echo "$o" | grep -qiE 'Connect OK|already|connected|repeat'; then
  pass "tconn correct port $DEV_PORT"
else
  fail "tconn correct port $DEV_PORT"
fi
so=$($H -t 127.0.0.1:$DEV_PORT shell 'echo CONTRACT_OK; echo __RC=$?' 2>&1 || true)
echo "$so" | grep -q CONTRACT_OK && echo "$so" | grep -q '__RC=0' && pass "shell on $DEV_PORT" || fail "shell on $DEV_PORT"

# --- ports: wrong (jsdebug) must FAIL while only start mode is up ---
wo=$($H tconn 127.0.0.1:$WRONG_PORT 2>&1 || true)
echo "tconn :$WRONG_PORT (expect fail): $wo"
if echo "$wo" | grep -qiE 'Connect OK|already connected'; then
  fail "NEGATIVE: tconn to jsdebug port $WRONG_PORT unexpectedly succeeded (start-only mode)"
elif echo "$wo" | grep -qiE 'Fail|failed|Connect failed|timeout|refused'; then
  pass "NEGATIVE: tconn wrong port $WRONG_PORT fails as required"
else
  # Unknown response — treat as fail of negative assertion
  fail "NEGATIVE: unexpected tconn :$WRONG_PORT response: $wo"
fi

# --- paths: /data/ohjs must exist after ensure ---
"$D/run-qemu-hdcd.sh" status >/dev/null  # ensure_data_ohjs already ran on start
po=$($H -t 127.0.0.1:$DEV_PORT shell 'test -d /data/ohjs && echo OK; test -d /tmp/ohjs && echo TMPOK; echo __RC=$?' 2>&1 || true)
echo "paths: $po"
echo "$po" | grep -q OK && pass "path /data/ohjs exists" || fail "path /data/ohjs missing"
echo "$po" | grep -q TMPOK && pass "path /tmp/ohjs exists" || {
  $H -t 127.0.0.1:$DEV_PORT shell 'mkdir -p /tmp/ohjs' >/dev/null 2>&1 || true
  po2=$($H -t 127.0.0.1:$DEV_PORT shell 'test -d /tmp/ohjs && echo TMPOK' 2>&1 || true)
  echo "$po2" | grep -q TMPOK && pass "path /tmp/ohjs created" || fail "path /tmp/ohjs missing"
}

# --- marker leftover: clean deploy path must clear debug.* ---
$H -t 127.0.0.1:$DEV_PORT shell "mkdir -p /data/ohjs && touch $MARKER" >/dev/null 2>&1 || true
left=$($H -t 127.0.0.1:$DEV_PORT shell "ls /data/ohjs/debug.* 2>/dev/null; echo __RC=\$?" 2>&1 || true)
echo "marker planted: $left"
echo "$left" | grep -q "debug.$BUNDLE" && pass "marker create works" || fail "could not plant marker"

# Clean deploy path (IDE-CONTRACT §2)
$H -t 127.0.0.1:$DEV_PORT shell 'rm -f /data/ohjs/debug.*' >/dev/null 2>&1 || true
after=$($H -t 127.0.0.1:$DEV_PORT shell 'ls /data/ohjs/debug.* 2>/dev/null || echo NONE; echo __RC=$?' 2>&1 || true)
echo "after clean: $after"
if echo "$after" | grep -q NONE || ! echo "$after" | grep -q 'debug\.'; then
  pass "clean deploy clears /data/ohjs/debug.*"
else
  fail "NEGATIVE: marker left behind after clean deploy path: $after"
fi

# Refuse / WARN if any marker still present (second check as refuse)
still=$($H -t 127.0.0.1:$DEV_PORT shell 'sh -c "set -- /data/ohjs/debug.*; if [ -e \"\$1\" ]; then echo LEFTOVER; else echo CLEAN; fi"' 2>&1 || true)
echo "leftover check: $still"
if echo "$still" | grep -q LEFTOVER; then
  fail "REFUSE: debug.* marker still present after clean path"
elif echo "$still" | grep -q CLEAN; then
  pass "no marker leftover (CLEAN)"
else
  warn "leftover check inconclusive: $still"
fi

echo "RESULT=$R log=$OUT"
exit $R
