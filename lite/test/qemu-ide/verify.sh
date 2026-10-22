#!/bin/bash
# Verify run-qemu-hdcd.sh env with host hdc 3.2.0c: tconn, shell, file send, bm/aa/hilogcat flows with __RC marker.
set -u
D=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
HDC=${HDC:-/workspace/hdcd-port/hdc-host}; PORT=${HDCD_PORT:-8710}
export OHOS_HDC_SERVER_PORT=${OHOS_HDC_SERVER_PORT:-8711}
H="$HDC -s 127.0.0.1:$OHOS_HDC_SERVER_PORT"; T="-t 127.0.0.1:$PORT"; R=0
pass(){ echo "[PASS] $*"; }; fail(){ echo "[FAIL] $*"; R=1; }
sh_rc(){ $H $T shell "$1; echo __RC=\$?" 2>&1; }
"$D/run-qemu-hdcd.sh" start || exit 1
trap '$H kill >/dev/null 2>&1; "$D/run-qemu-hdcd.sh" stop >/dev/null' EXIT
o=$($H tconn 127.0.0.1:$PORT 2>&1); echo "tconn: $o"; echo "$o" | grep -q 'Connect OK' && pass tconn || fail tconn
o=$(sh_rc 'echo hello'); echo "$o"; echo "$o" | grep -q '__RC=0' && pass "shell + __RC" || fail shell
o=$(sh_rc 'false'); echo "$o" | grep -q '__RC=1' && pass "__RC nonzero ($o)" || fail "__RC nonzero: $o"
W=$(mktemp -d); printf '{"app":{"bundleName":"com.ohjs.demo"},"module":{"abilities":[{"name":"MainAbility"}]}}' > $W/config.json
(cd $W && zip -q demo.hap config.json)
o=$($H $T file send $W/demo.hap /tmp/ohjs/demo.hap 2>&1); echo "send: $o"; echo "$o" | grep -q 'FileTransfer finish' && pass "file send hap" || fail "file send"
o=$($H $T shell 'hilogcat > /tmp/ohjs/hilog.cap 2>&1 & echo $! > /tmp/ohjs/hilogcat.pid' 2>&1)
o=$(sh_rc 'bm set -s disable'); echo "$o"; echo "$o" | grep -q '^success' && pass "bm set -s disable" || fail "bm set"
o=$(sh_rc 'bm install -p /tmp/ohjs/demo.hap'); echo "$o"; echo "$o" | grep -q 'install success !' && echo "$o" | grep -q __RC=0 && pass "bm install" || fail "bm install"
o=$(sh_rc 'aa start -p com.ohjs.demo -n MainAbility'); echo "$o"; echo "$o" | grep -q 'receive command: start' && ! echo "$o" | grep -q 'Failed to run' && pass "aa start" || fail "aa start"
o=$(sh_rc 'aa dump -a'); echo "$o"; echo "$o" | grep -q '\[com.ohjs.demo\]\[MainAbility\]' && pass "aa dump" || fail "aa dump"
o=$(sh_rc 'aa terminate -p com.ohjs.demo'); echo "$o"; ! echo "$o" | grep -q 'Failed' && pass "aa terminate" || fail "aa terminate"
o=$(sh_rc 'bm uninstall -n com.ohjs.demo'); echo "$o"; echo "$o" | grep -q 'uninstall success !' && pass "bm uninstall" || fail "bm uninstall"
o=$(sh_rc 'aa start -p com.ohjs.demo -n MainAbility'); echo "$o" | grep -q 'Failed to run the command' && pass "aa start after uninstall fails (text, __RC=0 like upstream)" || fail "neg aa"
sleep 1
o=$($H $T shell 'kill $(cat /tmp/ohjs/hilogcat.pid); cat /tmp/ohjs/hilog.cap' 2>&1); echo "--- hilogcat capture:"; echo "$o"
echo "$o" | grep -q 'Hello from MainAbility' && pass "hilogcat stream captured app log" || fail "hilogcat"
o=$(timeout 4 $H $T shell 'hilogcat' 2>&1 & sleep 1.5; $H $T shell 'aa start -p x -n y' >/dev/null 2>&1; wait); echo "$o" | grep -q 'start x.y' && pass "hilogcat foreground stream (stop = kill hdc client)" || fail "hilogcat fg: $o"
sleep 1; o=$($H $T shell 'ps -ef | grep -c "[t]ail -n 0 -f"' 2>&1); echo "leftover hilogcat procs: $o"
o=$(timeout 4 $H $T hilog 2>&1 & sleep 1.5; $H $T shell 'aa start -p hilogfb -n z' >/dev/null 2>&1; wait); echo "hdc hilog: $o"
echo "$o" | grep -q 'start hilogfb.z' && pass "hdc hilog -> hilogcat fallback" || fail "hdc hilog fallback"
o=$($H $T hilog -h 2>&1); echo "hdc hilog -h: $o"; echo "$o" | grep -q 'Usage: hilogcat' && pass "hdc hilog -h -> hilogcat -h" || fail "hilog -h"
sleep 1; $H $T shell 'pkill -f "tail -n 0 -f" ; true' >/dev/null 2>&1
echo "RESULT=$R"; exit $R
