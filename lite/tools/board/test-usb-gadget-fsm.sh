#!/bin/bash
# Unit tests for usb-gadget-fsm.sh — fake filesystem, no real VID/PID / kernel.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
R=0
pass(){ echo "[PASS] $*"; }
fail(){ echo "[FAIL] $*"; R=1; }

ROOT=$(mktemp -d /tmp/usb-fsm-XXXXXX)
trap 'rm -rf "$ROOT"' EXIT

export CFG="$ROOT/config"
export SYS_UDC_DIR="$ROOT/udc"
export PROC_FILESYSTEMS="$ROOT/filesystems"
export FFS_DIR="$ROOT/ffs"
export GNAME=hdc

mkdir -p "$CFG" "$SYS_UDC_DIR"
# Start WITHOUT configfs usb_gadget and without configfs in proc
printf 'nodev\tsysfs\n' > "$PROC_FILESYSTEMS"

# shellcheck source=usb-gadget-fsm.sh
. "$HERE/usb-gadget-fsm.sh"

echo "==== test-usb-gadget-fsm root=$ROOT ===="

# 1) ABSENT when no usb_gadget
st=$(fsm_state)
[ "$st" = ABSENT ] && pass "state ABSENT without configfs" || fail "state=$st want ABSENT"

# 2) configfs missing error
if fsm_require_configfs 2>/tmp/fsm-err.txt; then
  fail "require_configfs should fail"
else
  grep -q FSM_ERR:configfs_missing /tmp/fsm-err.txt && pass "configfs_missing error" || fail "wrong err $(cat /tmp/fsm-err.txt)"
fi

# 3) Enable configfs tree → CONFIGFS_READY
mkdir -p "$CFG/usb_gadget"
printf 'nodev\tconfigfs\nnodev\tfunctionfs\n' > "$PROC_FILESYSTEMS"
st=$(fsm_state)
[ "$st" = CONFIGFS_READY ] && pass "state CONFIGFS_READY" || fail "state=$st want CONFIGFS_READY"
fsm_configfs_in_proc && pass "configfs in proc" || fail "configfs proc"
fsm_functionfs_in_proc && pass "functionfs in proc" || fail "functionfs proc"

# 4) UDC missing
if fsm_require_udc 2>/tmp/fsm-err.txt; then
  fail "require_udc should fail when empty"
else
  grep -q FSM_ERR:udc_missing /tmp/fsm-err.txt && pass "udc_missing error" || fail "udc err"
fi

# 5) Create gadget → GADGET_CREATED
fsm_create_gadget_tree >/dev/null
st=$(fsm_state)
[ "$st" = GADGET_CREATED ] && pass "state GADGET_CREATED" || fail "state=$st want GADGET_CREATED"

# 6) FFS mounted marker → FFS_MOUNTED
fsm_mark_ffs_mounted
st=$(fsm_state)
[ "$st" = FFS_MOUNTED ] && pass "state FFS_MOUNTED" || fail "state=$st want FFS_MOUNTED"

# 7) Bind fail (bad UDC)
if fsm_try_bind bogus-udc 2>/tmp/fsm-err.txt; then
  fail "bind should fail"
else
  grep -q FSM_ERR:bind_fail_no_udc /tmp/fsm-err.txt && pass "bind_fail_no_udc" || fail "bind err $(cat /tmp/fsm-err.txt)"
fi
st=$(fsm_state)
[ "$st" = FFS_MOUNTED ] && pass "state unchanged after bind fail" || fail "state=$st after fail"

# 8) Bind OK
: > "$SYS_UDC_DIR/dummy_udc.0"
fsm_try_bind dummy_udc.0
st=$(fsm_state)
[ "$st" = UDC_BOUND ] && pass "state UDC_BOUND" || fail "state=$st want UDC_BOUND"

# 9) Cleanup idempotent
fsm_cleanup_gadget
st=$(fsm_state)
[ "$st" = CONFIGFS_READY ] && pass "cleanup → CONFIGFS_READY" || fail "state=$st after cleanup"
fsm_cleanup_gadget
fsm_cleanup_gadget
pass "cleanup idempotent (×3)"

# 10) setup-usb-gadget.sh --dry-run / --check still work (real host, no fake CFG)
if "$HERE/setup-usb-gadget.sh" --dry-run >/tmp/usb-dry.txt 2>&1; then
  grep -q 'DRY-RUN: no changes made' /tmp/usb-dry.txt && pass "setup-usb-gadget --dry-run" || fail "dry-run text"
else
  fail "dry-run exit"
fi
"$HERE/setup-usb-gadget.sh" --check >/tmp/usb-chk.txt 2>&1 || true
# exit 1 expected off-board
grep -qE 'MISS|OK' /tmp/usb-chk.txt && pass "setup-usb-gadget --check runs" || fail "check output"

echo "RESULT=$R"
exit $R
