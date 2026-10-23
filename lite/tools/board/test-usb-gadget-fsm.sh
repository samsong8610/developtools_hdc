#!/bin/bash
# Unit tests for usb-gadget-fsm.sh — fake filesystem, no real VID/PID / kernel.
# Cross-link: board probes U1–U8 in lite/docs/BOARD-RECOVERY.md §1; see README-USB-GADGET.md.
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


# ---- Negative / edge cases ----
ROOT2=$(mktemp -d /tmp/usb-fsm-neg-XXXXXX)
export CFG="$ROOT2/config"
export SYS_UDC_DIR="$ROOT2/udc"
export PROC_FILESYSTEMS="$ROOT2/filesystems"
export FFS_DIR="$ROOT2/ffs"
export GNAME=hdc
mkdir -p "$CFG" "$SYS_UDC_DIR"
printf 'nodev\tsysfs\n' > "$PROC_FILESYSTEMS"
# re-source not needed — functions use env vars

echo "==== NEG/edge FunctionFS FSM root=$ROOT2 ===="

# N1) cleanup when ABSENT (idempotent no-op)
st=$(fsm_state)
[ "$st" = ABSENT ] || fail "neg setup ABSENT got $st"
fsm_cleanup_gadget
fsm_cleanup_gadget
st=$(fsm_state)
[ "$st" = ABSENT ] && pass "NEG: cleanup from ABSENT stays ABSENT" || fail "state=$st after ABSENT cleanup"

# N2) bind before gadget exists
if fsm_try_bind anything 2>/tmp/fsm-neg.txt; then
  fail "NEG: bind without gadget should fail"
else
  grep -q FSM_ERR:bind_fail_no_gadget /tmp/fsm-neg.txt && pass "NEG: bind_fail_no_gadget" || \
    grep -q FSM_ERR:bind_fail_no_udc /tmp/fsm-neg.txt && pass "NEG: bind fail before gadget (no_udc first)" || \
    fail "NEG: unexpected bind err $(cat /tmp/fsm-neg.txt)"
fi

# N3) configfs present but functionfs missing from proc (edge — still CONFIGFS_READY)
mkdir -p "$CFG/usb_gadget"
printf 'nodev\tconfigfs\n' > "$PROC_FILESYSTEMS"   # no functionfs line
st=$(fsm_state)
[ "$st" = CONFIGFS_READY ] && pass "NEG: CONFIGFS_READY without functionfs in proc" || fail "state=$st"
fsm_functionfs_in_proc && fail "NEG: functionfs should be absent" || pass "NEG: functionfs missing detected"

# N4) require_udc with explicit wrong name while other UDC exists
: > "$SYS_UDC_DIR/real_udc.0"
if fsm_require_udc wrong-udc 2>/tmp/fsm-neg.txt; then
  fail "NEG: require_udc wrong name should fail"
else
  grep -q FSM_ERR:udc_missing /tmp/fsm-neg.txt && pass "NEG: udc_missing for wrong explicit name" || fail "NEG udc err"
fi
fsm_require_udc real_udc.0 && pass "NEG control: correct UDC accepted" || fail "correct UDC rejected"

# N5) bind_fail_no_gadget after tree removed mid-flight
fsm_create_gadget_tree >/dev/null
rm -rf "$CFG/usb_gadget/$GNAME"
if fsm_try_bind real_udc.0 2>/tmp/fsm-neg.txt; then
  fail "NEG: bind after gadget rm should fail"
else
  grep -q FSM_ERR:bind_fail_no_gadget /tmp/fsm-neg.txt && pass "NEG: bind_fail_no_gadget after rm" || fail "err=$(cat /tmp/fsm-neg.txt)"
fi

# N6) double-bind / rebind overwrite
fsm_create_gadget_tree >/dev/null
fsm_mark_ffs_mounted
fsm_try_bind real_udc.0
st=$(fsm_state)
[ "$st" = UDC_BOUND ] || fail "precondition UDC_BOUND got $st"
: > "$SYS_UDC_DIR/other_udc.1"
fsm_try_bind other_udc.1
bound=$(cat "$CFG/usb_gadget/$GNAME/UDC" 2>/dev/null || true)
[ "$bound" = other_udc.1 ] && pass "NEG/edge: rebind switches UDC" || fail "UDC=$bound want other_udc.1"
st=$(fsm_state)
[ "$st" = UDC_BOUND ] && pass "NEG/edge: still UDC_BOUND after rebind" || fail "state=$st"

# N7) unbind via empty UDC then state drops from UDC_BOUND
echo "" > "$CFG/usb_gadget/$GNAME/UDC"
st=$(fsm_state)
# FFS marker still present → FFS_MOUNTED
[ "$st" = FFS_MOUNTED ] && pass "NEG/edge: clear UDC → FFS_MOUNTED" || fail "state=$st want FFS_MOUNTED after unbind"

# N8) bogus empty UDC name bind
if fsm_try_bind "" 2>/tmp/fsm-neg.txt; then
  fail "NEG: bind empty UDC should fail"
else
  grep -qE 'FSM_ERR:bind_fail_no_udc' /tmp/fsm-neg.txt && pass "NEG: bind empty UDC → no_udc" || pass "NEG: bind empty UDC fails ($(cat /tmp/fsm-neg.txt | tr '\n' ' '))"
fi

# N9) create twice (idempotent dirs)
fsm_cleanup_gadget
g1=$(fsm_create_gadget_tree)
g2=$(fsm_create_gadget_tree)
[ -d "$g1" ] && [ -d "$g2" ] && pass "NEG/edge: create_gadget_tree twice OK" || fail "double create"

fsm_cleanup_gadget
rm -rf "$ROOT2"

echo "RESULT=$R"
exit $R
