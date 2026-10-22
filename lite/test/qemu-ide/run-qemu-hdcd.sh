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
