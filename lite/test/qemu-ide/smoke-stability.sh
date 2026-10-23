#!/bin/bash
# qemu-ide stability: reconnect, consecutive file send, parallel shell (+ optional verify-contract).
# Host-only — no real board. Requires run-qemu-hdcd.sh start (qemu-user hdcd on :8710).
# Log: lite/test/qemu-ide-stability.log. Keeps run-qemu-hdcd healthy (no server kill).
# Stub aa/bm limits: see lite/test/qemu-ide/README.md (this smoke does not call aa).
# Env: N_RECONN N_SEND N_PARALLEL SKIP_CONTRACT=1 HDC HDCD_PORT OHOS_HDC_SERVER_PORT
set -u
D=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
PORT_ROOT=${PORT:-/workspace/hdcd-port}
HDC=${HDC:-$PORT_ROOT/hdc-host}
DEV_PORT=${HDCD_PORT:-8710}
export OHOS_HDC_SERVER_PORT=${OHOS_HDC_SERVER_PORT:-8711}
H="$HDC -s 127.0.0.1:$OHOS_HDC_SERVER_PORT"
T="-t 127.0.0.1:$DEV_PORT"
OUT=${OUT_LOG:-$PORT_ROOT/hdc/lite/test/qemu-ide-stability.log}
R=0
N_RECONN=${N_RECONN:-5}
N_SEND=${N_SEND:-5}
N_PARALLEL=${N_PARALLEL:-4}

mkdir -p "$(dirname "$OUT")"
exec > >(tee "$OUT") 2>&1

pass(){ echo "[PASS] $*"; }
fail(){ echo "[FAIL] $*"; R=1; }

ensure_env() {
  if ! "$D/run-qemu-hdcd.sh" status | grep -q running; then
    "$D/run-qemu-hdcd.sh" start || { echo "cannot start hdcd"; exit 2; }
  fi
  # Ensure host server answers (do not kill -r unless dead)
  if ! $H list targets >/dev/null 2>&1; then
    $H start >/dev/null 2>&1 || true
    sleep 0.5
  fi
  local o
  o=$($H tconn 127.0.0.1:$DEV_PORT 2>&1 || true)
  echo "initial tconn: $o"
  echo "$o" | grep -qiE 'Connect OK|already|connected' || {
    # retry once after short wait
    sleep 1
    o=$($H tconn 127.0.0.1:$DEV_PORT 2>&1 || true)
    echo "retry tconn: $o"
  }
}

tconn_ok() {
  local o
  o=$($H tconn 127.0.0.1:$DEV_PORT 2>&1 || true)
  echo "$o" | grep -qiE 'Connect OK|already|connected|repeat'
}

shell_ok() {
  local o
  o=$($H $T shell 'echo STAB_OK; echo __RC=$?' 2>&1 || true)
  echo "$o" | grep -q STAB_OK && echo "$o" | grep -q '__RC=0'
}

echo "==== smoke-stability $(date '+%Y-%m-%d %H:%M:%S %z') ===="
echo "hdc=$HDC server=$OHOS_HDC_SERVER_PORT device=127.0.0.1:$DEV_PORT log=$OUT"
ensure_env
shell_ok && pass "baseline shell" || fail "baseline shell"

echo "== 1) disconnect / reconnect ×$N_RECONN"
for i in $(seq 1 "$N_RECONN"); do
  $H tconn 127.0.0.1:$DEV_PORT -remove >/dev/null 2>&1 || true
  sleep 0.3
  if tconn_ok && shell_ok; then
    pass "reconnect #$i"
  else
    # one more try
    sleep 0.5
    if tconn_ok && shell_ok; then
      pass "reconnect #$i (retry)"
    else
      fail "reconnect #$i"
    fi
  fi
done

echo "== 2) consecutive file send ×$N_SEND (1–5 MiB)"
W=$(mktemp -d /tmp/stab-send-XXXXXX)
for i in $(seq 1 "$N_SEND"); do
  # sizes 1,2,3,4,5 MiB cycling
  sz=$(( (i - 1) % 5 + 1 ))
  f="$W/blob-$i.bin"
  dd if=/dev/urandom of="$f" bs=1M count="$sz" status=none 2>/dev/null || \
    dd if=/dev/zero of="$f" bs=1M count="$sz" status=none
  local_sha=$(sha256sum "$f" | awk '{print $1}')
  remote="/tmp/ohjs/stab-$i.bin"
  $H $T shell "mkdir -p /tmp/ohjs" >/dev/null 2>&1 || true
  o=$($H $T file send "$f" "$remote" 2>&1 || true)
  echo "send #$i (${sz}MiB): $(echo "$o" | tr '\n' ' ' | tail -c 120)"
  if ! echo "$o" | grep -qi 'FileTransfer finish'; then
    fail "file send #$i (no finish)"
    continue
  fi
  remote_sha=$($H $T shell "sha256sum $remote 2>/dev/null | awk '{print \$1}'; echo __RC=\$?" 2>&1 | awk '/^[0-9a-f]{64}$/{print; exit}')
  if [ -z "$remote_sha" ]; then
    # fallback: recv back
    back="$W/back-$i.bin"
    $H $T file recv "$remote" "$back" >/dev/null 2>&1 || true
    if [ -f "$back" ]; then
      remote_sha=$(sha256sum "$back" | awk '{print $1}')
    fi
  fi
  if [ "$local_sha" = "$remote_sha" ]; then
    pass "file send #$i ${sz}MiB sha match"
  else
    fail "file send #$i sha mismatch local=$local_sha remote=$remote_sha"
  fi
done
rm -rf "$W"

echo "== 3) parallel shell ×$N_PARALLEL"
PDIR=$(mktemp -d /tmp/stab-par-XXXXXX)
pids=()
for i in $(seq 1 "$N_PARALLEL"); do
  (
    o=$($H $T shell "echo PAR_$i; echo __RC=\$?" 2>&1 || true)
    if echo "$o" | grep -q "PAR_$i" && echo "$o" | grep -q '__RC=0'; then
      echo OK > "$PDIR/$i"
    else
      echo "$o" > "$PDIR/$i.err"
      echo FAIL > "$PDIR/$i"
    fi
  ) &
  pids+=($!)
done
for p in "${pids[@]}"; do wait "$p" || true; done
okn=0
for i in $(seq 1 "$N_PARALLEL"); do
  if [ -f "$PDIR/$i" ] && grep -q OK "$PDIR/$i"; then
    okn=$((okn + 1))
  else
    fail "parallel shell #$i ($(cat "$PDIR/$i.err" 2>/dev/null | tr '\n' ' ' | tail -c 80))"
  fi
done
[ "$okn" = "$N_PARALLEL" ] && pass "parallel shell $okn/$N_PARALLEL" || fail "parallel shell only $okn/$N_PARALLEL"
rm -rf "$PDIR"

# Health check — leave env usable for G2
if tconn_ok && shell_ok; then
  pass "post-smoke health (tconn+shell)"
else
  # try soft recover without killing server
  $H tconn 127.0.0.1:$DEV_PORT >/dev/null 2>&1 || true
  if shell_ok; then
    pass "post-smoke health (after re-tconn)"
  else
    fail "post-smoke health"
  fi
fi

# IDE-CONTRACT regression (SKIP_CONTRACT=1 to skip)
if [ "${SKIP_CONTRACT:-0}" != 1 ]; then
  echo "== 4) verify-contract"
  if "$D/verify-contract.sh"; then
    pass "verify-contract"
  else
    fail "verify-contract"
  fi
fi

echo "RESULT=$R log=$OUT"
exit $R
