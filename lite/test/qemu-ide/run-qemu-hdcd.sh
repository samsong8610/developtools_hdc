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
# ---- jsdebug mode: isolated netns so device-side :5001 is reachable ONLY through hdcd (hdc fport) ----
# Usage: run-qemu-hdcd.sh jsdebug [start|stop] ; env JERRY_BIN, JS_FILE, NS=ohjsdbg, HOST_PORT=18710
# netns has only loopback; host reaches hdcd via socat bridge 127.0.0.1:$HOST_PORT -> (netns) 127.0.0.1:$PORT.
if [ "${1:-}" = jsdebug ]; then
  NS=${NS:-ohjsdbg}; HP=${HOST_PORT:-18710}
  JB=${JERRY_BIN:-/workspace/hdcd-port/b/jerry-la64/bin/jerry}; JS=${JS_FILE:-$D/sample.js}
  NX="sudo ip netns exec $NS sudo -u $(id -un) env"
  if [ "${2:-start}" = stop ]; then
    pkill -f "socat TCP-LISTEN:$HP" 2>/dev/null; sudo ip netns pids $NS 2>/dev/null | xargs -r sudo kill 2>/dev/null
    sleep 0.5; sudo ip netns del $NS 2>/dev/null; echo "jsdebug stopped"; exit 0
  fi
  "$0" jsdebug stop >/dev/null
  mkdir -p "$OHJS_FAKEROOT/etc/hdcd" "$OHJS_FAKEROOT/data/hdcd" "$RUN" /tmp/ohjs
  printf '%s\n' const.security.developermode.state=true const.hdc.secure=0 const.debuggable=1 persist.hdc.root=1 \
    persist.hdc.mode=tcp persist.hdc.mode.tcp=enable persist.hdc.port=$PORT > "$OHJS_FAKEROOT/etc/hdcd/hdcd.para"
  rm -f "$OHJS_FAKEROOT/data/hdcd/persist.para"
  sudo ip netns add $NS && sudo ip netns exec $NS ip link set lo up
  $NX HDC_OSAL_DEFAULT_PARA="$OHJS_FAKEROOT/etc/hdcd/hdcd.para" HDC_OSAL_PERSIST_PARA="$OHJS_FAKEROOT/data/hdcd/persist.para" \
    HDC_OSAL_REEXEC_WRAPPER=qemu-loongarch64 setsid qemu-loongarch64 "$BIN" -t -l4 > "$RUN/hdcd-ns.log" 2>&1 < /dev/null &
  cp "$JS" /tmp/ohjs/; JSB=/tmp/ohjs/$(basename "$JS")
  (cd /tmp/ohjs && $NX setsid qemu-loongarch64 "$JB" --start-debug-server --debug-port 5001 --log-level 2 "$(basename "$JS")" > "$RUN/jerry.log" 2>&1 < /dev/null &)
  setsid socat TCP-LISTEN:$HP,bind=127.0.0.1,reuseaddr,fork EXEC:"sudo ip netns exec $NS socat - TCP\:127.0.0.1\:$PORT" > "$RUN/socat.log" 2>&1 < /dev/null &
  for i in $(seq 1 20); do grep -q "TCP listen on port:\[$PORT\]" "$RUN/hdcd-ns.log" 2>/dev/null && break; sleep 0.5; done
  grep -q "TCP listen on port:\[$PORT\]" "$RUN/hdcd-ns.log" || { echo "hdcd (netns) failed"; tail "$RUN/hdcd-ns.log"; exit 1; }
  echo "jsdebug up: netns=$NS hdcd=127.0.0.1:$HP (bridge) jerry=netns:5001 js=$JSB logs=$RUN/{hdcd-ns,jerry,socat}.log"
  exit 0
fi
case "${1:-start}" in
stop) [ -f "$PID" ] && kill "$(cat "$PID")" 2>/dev/null; pkill -f "qemu-loongarch64 $BIN" 2>/dev/null; rm -f "$PID"; echo stopped; exit 0;;
status) [ -f "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null && echo "running pid=$(cat "$PID") port=$PORT" || echo "not running"; exit 0;;
esac
command -v qemu-loongarch64 >/dev/null || { echo "need qemu-user (qemu-loongarch64)"; exit 1; }
[ -x "$BIN" ] || { echo "no hdcd at $BIN"; exit 1; }
mkdir -p "$OHJS_FAKEROOT"/{bin,etc/hdcd,data/hdcd,storage/app/run,storage/app/etc/bundles,storage/data/log} "$RUN" /tmp/ohjs
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
