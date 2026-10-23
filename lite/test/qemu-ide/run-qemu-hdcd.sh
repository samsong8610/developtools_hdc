#!/bin/bash
# One-command local IDE integration env:
#   loongarch64 static hdcd under qemu-loongarch64 (user mode), TCP :8710,
#   fake root ($OHJS_FAKEROOT) + stub bm/aa/hilogcat on PATH.
# Usage: run-qemu-hdcd.sh [start|stop|status]   (env: HDCD_BIN, HDCD_PORT=8710, OHJS_FAKEROOT)
# NOTE host hdc server also defaults to 8710 -> run host side with OHOS_HDC_SERVER_PORT=8711 (or other).
set -u
D=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
PORT=${HDCD_PORT:-8710}
BIN=${HDCD_BIN:-/workspace/hdcd-port/b/out/hdcd.stripped}
export OHJS_FAKEROOT=${OHJS_FAKEROOT:-/tmp/ohjs-fakeroot}
RUN=$OHJS_FAKEROOT/run; PID=$RUN/hdcd.pid
# IDE / ACE gate default flag dir is /data/ohjs/debug.<bundle> (see JS-DEBUG.md §E).
# qemu-user shares the host FS; create a writable /data/ohjs for marker e2e.
ensure_data_ohjs() {
  if [ -d /data/ohjs ] && [ -w /data/ohjs ]; then return 0; fi
  if mkdir -p /data/ohjs 2>/dev/null; then return 0; fi
  sudo mkdir -p /data/ohjs && sudo chown "$(id -un):$(id -gn)" /data/ohjs
}
# ---- jsdebug mode: isolated netns so device-side :5001 is reachable ONLY through hdcd (hdc fport) ----
# Usage: run-qemu-hdcd.sh jsdebug [start|stop] ; env JERRY_BIN, JS_FILE, NS=ohjsdbg, HOST_PORT=18710,
#   JERRY_ARGS (default: jerry-main debug flags), JERRY_ENV ("K=V ..." passed into the netns, e.g. ACE_DEBUGGER_WAIT=1)
# netns has only loopback; host reaches hdcd via socat bridge 127.0.0.1:$HOST_PORT -> (netns) 127.0.0.1:$PORT.
if [ "${1:-}" = jsdebug ]; then
  NS=${NS:-ohjsdbg}; HP=${HOST_PORT:-18710}
  JB=${JERRY_BIN:-/workspace/hdcd-port/b/jerry-la64/bin/jerry}; JS=${JS_FILE:-$D/sample.js}
  NX="sudo ip netns exec $NS sudo -u $(id -un) env"
  VETH_H=veth-ohjs-h; VETH_N=veth-ohjs-n
  NS_IP=${JSDEBUG_NS_IP:-10.200.1.2}
  if [ "${2:-start}" = stop ]; then
    pkill -f "socat TCP-LISTEN:$HP" 2>/dev/null || true
    pkill -f "netns-bridge.py $HP" 2>/dev/null || true
    sudo ip netns pids $NS 2>/dev/null | xargs -r sudo kill 2>/dev/null || true
    sleep 0.5
    sudo ip link del "$VETH_H" 2>/dev/null || true
    sudo ip netns del $NS 2>/dev/null || true
    echo "jsdebug stopped"; exit 0
  fi
  "$0" jsdebug stop >/dev/null
  mkdir -p "$OHJS_FAKEROOT/etc/hdcd" "$OHJS_FAKEROOT/data/hdcd" "$OHJS_FAKEROOT/data/ohjs" "$RUN" /tmp/ohjs
  ensure_data_ohjs
  printf '%s\n' const.security.developermode.state=true const.hdc.secure=0 const.debuggable=1 persist.hdc.root=1 \
    persist.hdc.mode=tcp persist.hdc.mode.tcp=enable persist.hdc.port=$PORT > "$OHJS_FAKEROOT/etc/hdcd/hdcd.para"
  rm -f "$OHJS_FAKEROOT/data/hdcd/persist.para"
  sudo ip netns add $NS && sudo ip netns exec $NS ip link set lo up
  # veth so host reaches netns hdcd without socat (fport still stays inside netns)
  sudo ip link add "$VETH_H" type veth peer name "$VETH_N"
  sudo ip link set "$VETH_N" netns $NS
  sudo ip addr add 10.200.1.1/24 dev "$VETH_H"
  sudo ip link set "$VETH_H" up
  sudo ip netns exec $NS ip addr add ${NS_IP}/24 dev "$VETH_N"
  sudo ip netns exec $NS ip link set "$VETH_N" up
  $NX HDC_OSAL_DEFAULT_PARA="$OHJS_FAKEROOT/etc/hdcd/hdcd.para" HDC_OSAL_PERSIST_PARA="$OHJS_FAKEROOT/data/hdcd/persist.para" \
    HDC_OSAL_REEXEC_WRAPPER=qemu-loongarch64 setsid qemu-loongarch64 "$BIN" -t -l4 > "$RUN/hdcd-ns.log" 2>&1 < /dev/null &
  cp "$JS" /tmp/ohjs/; JSB=/tmp/ohjs/$(basename "$JS")
  (cd /tmp/ohjs && $NX ${JERRY_ENV:-} setsid qemu-loongarch64 "$JB" ${JERRY_ARGS---start-debug-server --debug-port 5001 --log-level 2} "$(basename "$JS")" > "$RUN/jerry.log" 2>&1 < /dev/null &)
  # Optional localhost:$HP alias via socat/python for callers that still use HOST_PORT=18710
  if command -v socat >/dev/null 2>&1; then
    setsid socat TCP-LISTEN:$HP,bind=127.0.0.1,reuseaddr,fork TCP:${NS_IP}:$PORT > "$RUN/socat.log" 2>&1 < /dev/null &
  else
    setsid python3 "$D/netns-bridge.py" "$HP" -- python3 "$D/tcp-connect.py" "$NS_IP" "$PORT" > "$RUN/socat.log" 2>&1 < /dev/null &
  fi
  for i in $(seq 1 20); do grep -q "TCP listen on port:\[$PORT\]" "$RUN/hdcd-ns.log" 2>/dev/null && break; sleep 0.5; done
  grep -q "TCP listen on port:\[$PORT\]" "$RUN/hdcd-ns.log" || { echo "hdcd (netns) failed"; tail "$RUN/hdcd-ns.log"; exit 1; }
  echo "jsdebug up: netns=$NS hdcd=${NS_IP}:$PORT (veth) alias=127.0.0.1:$HP jerry=netns:5001 js=$JSB marker=/data/ohjs/debug.<bundle> logs=$RUN/{hdcd-ns,jerry,socat}.log"
  exit 0
fi
case "${1:-start}" in
stop) [ -f "$PID" ] && kill "$(cat "$PID")" 2>/dev/null; pkill -f "qemu-loongarch64 $BIN" 2>/dev/null; rm -f "$PID"; echo stopped; exit 0;;
status) [ -f "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null && echo "running pid=$(cat "$PID") port=$PORT" || echo "not running"; exit 0;;
esac
command -v qemu-loongarch64 >/dev/null || { echo "need qemu-user (qemu-loongarch64)"; exit 1; }
[ -x "$BIN" ] || { echo "no hdcd at $BIN"; exit 1; }
mkdir -p "$OHJS_FAKEROOT"/{bin,etc/hdcd,data/hdcd,data/ohjs,storage/app/run,storage/app/etc/bundles,storage/data/log} "$RUN" /tmp/ohjs
ensure_data_ohjs
install -m755 "$D"/stubs/{bm,aa,hilogcat} "$OHJS_FAKEROOT/bin/"
cat > "$OHJS_FAKEROOT/etc/hdcd/hdcd.para" <<P
const.security.developermode.state=true
const.hdc.secure=0
const.debuggable=1
persist.hdc.root=1
persist.hdc.mode=tcp
persist.hdc.mode.tcp=enable
persist.hdc.port=$PORT
P
"$0" stop >/dev/null
env PATH="$OHJS_FAKEROOT/bin:/usr/bin:/bin" \
    HDC_OSAL_DEFAULT_PARA="$OHJS_FAKEROOT/etc/hdcd/hdcd.para" \
    HDC_OSAL_PERSIST_PARA="$OHJS_FAKEROOT/data/hdcd/persist.para" \
    HDC_OSAL_REEXEC_WRAPPER=qemu-loongarch64 \
  setsid qemu-loongarch64 "$BIN" -t -l4 > "$RUN/hdcd.log" 2>&1 < /dev/null &
echo $! > "$PID"
for i in $(seq 1 20); do grep -q "TCP listen on port:\[$PORT\]" "$RUN/hdcd.log" && break; sleep 0.5; done
if grep -q "TCP listen on port:\[$PORT\]" "$RUN/hdcd.log"; then
  echo "hdcd up: 127.0.0.1:$PORT pid=$(cat "$PID") fakeroot=$OHJS_FAKEROOT log=$RUN/hdcd.log"
else echo "hdcd failed to start"; tail -20 "$RUN/hdcd.log"; exit 1; fi
