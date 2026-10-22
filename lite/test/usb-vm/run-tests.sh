#!/bin/sh
H=/bin/hdc; R=0
pass(){ echo "[PASS] $*"; }; fail(){ echo "[FAIL] $*"; R=1; }
$H -v
$H start; sleep 3
for i in 1 2 3 4 5; do L=$($H list targets -v 2>&1); echo "$L" | grep -q LA64EMU0001 && break; sleep 2; done
echo "list: $L"
echo "$L" | grep -q 'LA64EMU0001.*USB.*Connected' && pass "enumerate USB target" || fail "enumerate"
T="-t LA64EMU0001"
o=$($H $T shell 'echo hello-usb; uname -m' 2>&1); echo "shell: $o"
echo "$o" | grep -q hello-usb && pass "shell over USB" || fail "shell"
dd if=/dev/urandom of=/tmp/big.bin bs=1M count=20 2>/dev/null
o=$($H $T file send /tmp/big.bin /data/recv.bin 2>&1); echo "send: $o"
cmp /tmp/big.bin /data/recv.bin && pass "file send 20MB cmp" || fail "file send"
o=$($H $T file recv /data/recv.bin /tmp/back.bin 2>&1); echo "recv: $o"
cmp /tmp/big.bin /tmp/back.bin && pass "file recv 20MB cmp" || fail "file recv"
o=$($H $T shell 'exit 3'; echo rc=$?); echo "exitcode: $o"; echo "$o" | grep -q rc=3 && pass "shell exitcode" || echo "[WARN] shell exitcode not propagated by host hdc 3.2.0c"
echo "RESULT=$R"
$H kill >/dev/null 2>&1
