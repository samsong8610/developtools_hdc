# shellcheck shell=bash
# USB gadget / FunctionFS state machine helpers (sourced by setup-usb-gadget.sh + tests).
# No real VID/PID required. Override CFG / SYS_UDC_DIR / PROC_FILESYSTEMS for unit tests.
#
# States (logical): ABSENT → CONFIGFS_READY → GADGET_CREATED → FFS_MOUNTED → UDC_BOUND
# Failure transitions: missing configfs, missing UDC, bind refused, cleanup always idempotent.

: "${CFG:=/sys/kernel/config}"
: "${SYS_UDC_DIR:=/sys/class/udc}"
: "${PROC_FILESYSTEMS:=/proc/filesystems}"
: "${FFS_DIR:=/dev/usb-ffs/hdc}"
: "${GNAME:=hdc}"

fsm_state() {
  # Print one of: ABSENT CONFIGFS_READY GADGET_CREATED FFS_MOUNTED UDC_BOUND
  local g="${1:-$CFG/usb_gadget/$GNAME}"
  if [ ! -d "$CFG/usb_gadget" ]; then
    echo ABSENT; return
  fi
  if [ ! -d "$g" ]; then
    echo CONFIGFS_READY; return
  fi
  if [ -e "$g/UDC" ] && [ -n "$(cat "$g/UDC" 2>/dev/null || true)" ]; then
    echo UDC_BOUND; return
  fi
  # FFS mount is tracked via a marker file in tests; on real systems use mountpoint
  if [ -f "${g}/.ffs_mounted" ] || mountpoint -q "$FFS_DIR" 2>/dev/null; then
    echo FFS_MOUNTED; return
  fi
  echo GADGET_CREATED
}

fsm_have_configfs() {
  [ -d "$CFG/usb_gadget" ]
}

fsm_configfs_in_proc() {
  grep -q configfs "$PROC_FILESYSTEMS" 2>/dev/null
}

fsm_functionfs_in_proc() {
  grep -q functionfs "$PROC_FILESYSTEMS" 2>/dev/null
}

fsm_list_udc() {
  ls "$SYS_UDC_DIR" 2>/dev/null || true
}

# Error: configfs missing → transition fails (caller exits 1)
fsm_require_configfs() {
  if fsm_have_configfs; then return 0; fi
  echo "FSM_ERR:configfs_missing" >&2
  return 1
}

# Error: no UDC → cannot bind
fsm_require_udc() {
  local udc=${1:-}
  if [ -n "$udc" ] && [ -e "$SYS_UDC_DIR/$udc" ]; then return 0; fi
  if [ -z "$udc" ] && [ -n "$(fsm_list_udc)" ]; then return 0; fi
  echo "FSM_ERR:udc_missing" >&2
  return 1
}

# Simulate create gadget dirs under CFG (no kernel, no real VID write to hardware)
fsm_create_gadget_tree() {
  local g="$CFG/usb_gadget/$GNAME"
  mkdir -p "$g/strings/0x409" "$g/configs/b.1/strings/0x409" "$g/functions/ffs.hdc"
  : > "$g/idVendor"
  : > "$g/idProduct"
  : > "$g/UDC"   # empty = unbound
  echo "$g"
}

fsm_mark_ffs_mounted() {
  local g="$CFG/usb_gadget/$GNAME"
  mkdir -p "$g"
  : > "$g/.ffs_mounted"
}

# Bind fail: UDC name not in SYS_UDC_DIR
fsm_try_bind() {
  local g="$CFG/usb_gadget/$GNAME"
  local udc=$1
  if [ ! -e "$SYS_UDC_DIR/$udc" ]; then
    echo "FSM_ERR:bind_fail_no_udc:$udc" >&2
    return 1
  fi
  if [ ! -d "$g" ]; then
    echo "FSM_ERR:bind_fail_no_gadget" >&2
    return 1
  fi
  echo "$udc" > "$g/UDC"
  return 0
}

# Idempotent cleanup — safe if absent
fsm_cleanup_gadget() {
  local g=${1:-$CFG/usb_gadget/$GNAME}
  [ -d "$g" ] || return 0
  if [ -e "$g/UDC" ]; then
    echo "" > "$g/UDC" 2>/dev/null || true
  fi
  rm -rf "$g"
  return 0
}
