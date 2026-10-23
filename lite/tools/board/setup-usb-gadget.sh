#!/bin/bash
# Create a configfs USB gadget + FunctionFS mount for hdcd (-u).
# Default VID:PID 0x12d1:0x5000 is a PLACEHOLDER (same as qemu dummy_hcd e2e).
#
# Usage:
#   setup-usb-gadget.sh [--udc NAME] [--vid HEX] [--pid HEX] [--serial STR]
#                       [--gadget NAME] [--ffs-dir DIR] [--dry-run] [--check] [--clean]
#
# Env overrides: HDC_USB_UDC, HDC_USB_VID, HDC_USB_PID, HDC_USB_SERIAL, HDC_USB_GADGET,
#                HDC_USB_FFS_DIR (= /dev/usb-ffs/hdc).
#
# Idempotent: re-run cleans previous gadget of the same name then recreates.
# Does not start hdcd. Next step (printed): HDC_OSAL_USB_GADGET=... hdcd -u
# Exit codes: 0 = ok/dry-run; 1 = --check missing configfs/UDC (expected off-board);
#             2 = usage/error.
# Off-board: prefer --dry-run / --check. Full bind needs root + configfs + UDC.
set -eu
# Optional FSM helpers (unit-tested via test-usb-gadget-fsm.sh; safe if missing).
_FSM="$(cd "$(dirname "$0")" && pwd)/usb-gadget-fsm.sh"
[ -f "$_FSM" ] && . "$_FSM" || true

UDC=${HDC_USB_UDC:-}
VID=${HDC_USB_VID:-0x12d1}
PID=${HDC_USB_PID:-0x5000}
SERIAL=${HDC_USB_SERIAL:-OHJS0001}
GNAME=${HDC_USB_GADGET:-hdc}
FFS_DIR=${HDC_USB_FFS_DIR:-/dev/usb-ffs/hdc}
DRY=0
CHECK=0
CLEAN_ONLY=0
CFG=/sys/kernel/config

usage() {
  sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --udc) UDC=$2; shift 2 ;;
    --vid) VID=$2; shift 2 ;;
    --pid) PID=$2; shift 2 ;;
    --serial) SERIAL=$2; shift 2 ;;
    --gadget) GNAME=$2; shift 2 ;;
    --ffs-dir) FFS_DIR=$2; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --check) CHECK=1; shift ;;
    --clean) CLEAN_ONLY=1; shift ;;
    -h|--help) usage ;;
    *) echo "unknown: $1" >&2; usage ;;
  esac
done

# Normalize hex
case "$VID" in 0x*|0X*) ;; *) VID=0x$VID ;; esac
case "$PID" in 0x*|0X*) ;; *) PID=0x$PID ;; esac

G="$CFG/usb_gadget/$GNAME"

have_configfs() {
  [ -d "$CFG/usb_gadget" ] || return 1
  return 0
}

mount_configfs_if_needed() {
  if [ -d "$CFG/usb_gadget" ]; then return 0; fi
  if ! grep -q 'nodev\tconfigfs' /proc/filesystems 2>/dev/null && ! grep -q 'configfs' /proc/filesystems 2>/dev/null; then
    return 1
  fi
  mkdir -p "$CFG"
  mount -t configfs none "$CFG" 2>/dev/null || mount -t configfs configfs "$CFG" 2>/dev/null || return 1
  [ -d "$CFG/usb_gadget" ]
}

list_udc() {
  ls /sys/class/udc 2>/dev/null || true
}

cleanup_gadget() {
  local g=$1
  [ -d "$g" ] || return 0
  echo "Cleaning gadget $g ..." >&2
  # Unbind UDC first
  if [ -e "$g/UDC" ]; then
    echo "" > "$g/UDC" 2>/dev/null || true
  fi
  # Remove config function links
  if [ -d "$g/configs" ]; then
    find "$g/configs" -type l -exec rm -f {} + 2>/dev/null || true
  fi
  # Unmount functionfs if this gadget owned the mount
  if mountpoint -q "$FFS_DIR" 2>/dev/null; then
    umount "$FFS_DIR" 2>/dev/null || umount -l "$FFS_DIR" 2>/dev/null || true
  fi
  # Remove functions / configs / strings (order matters)
  rm -rf "$g"/functions/* 2>/dev/null || true
  rm -rf "$g"/configs/*/strings/* 2>/dev/null || true
  rm -rf "$g"/configs/* 2>/dev/null || true
  rm -rf "$g"/strings/* 2>/dev/null || true
  rmdir "$g"/functions 2>/dev/null || true
  rmdir "$g"/configs 2>/dev/null || true
  rmdir "$g"/strings 2>/dev/null || true
  rmdir "$g" 2>/dev/null || rm -rf "$g" 2>/dev/null || true
}

check_only() {
  echo "=== setup-usb-gadget --check ==="
  local ok=1
  if grep -q configfs /proc/filesystems 2>/dev/null; then
    echo "[OK] configfs in /proc/filesystems"
  else
    echo "[MISS] configfs not in /proc/filesystems"; ok=0
  fi
  if grep -q functionfs /proc/filesystems 2>/dev/null; then
    echo "[OK] functionfs in /proc/filesystems"
  else
    echo "[MISS] functionfs not in /proc/filesystems"; ok=0
  fi
  if [ -d "$CFG" ]; then
    echo "[OK] $CFG exists"
  else
    echo "[MISS] $CFG missing"; ok=0
  fi
  if have_configfs || mount_configfs_if_needed; then
    echo "[OK] usb_gadget visible at $CFG/usb_gadget"
  else
    echo "[MISS] cannot mount/see configfs usb_gadget (dry-run/check only on this host?)"
    ok=0
  fi
  local udcs
  udcs=$(list_udc)
  if [ -n "$udcs" ]; then
    echo "[OK] UDC(s): $udcs"
  else
    echo "[MISS] no /sys/class/udc entries (no device controller / not in device mode)"
    ok=0
  fi
  echo "Planned: gadget=$GNAME vid=$VID pid=$PID serial=$SERIAL ffs=$FFS_DIR udc=${UDC:-<first>}"
  if type fsm_state >/dev/null 2>&1; then echo "FSM state: $(fsm_state)"; fi
  [ "$ok" = 1 ] && return 0 || return 1
}

if [ "$CHECK" = 1 ]; then
  check_only
  exit $?
fi

if [ "$DRY" = 1 ]; then
  echo "DRY-RUN: would create gadget=$GNAME VID=$VID PID=$PID serial=$SERIAL ffs=$FFS_DIR udc=${UDC:-auto}"
  check_only || true
  echo "DRY-RUN: no changes made."
  exit 0
fi

if ! have_configfs && ! mount_configfs_if_needed; then
  echo "ERROR: configfs / usb_gadget not available. Use --check / --dry-run on a host without gadget support." >&2
  echo "On board: ensure CONFIG_USB_CONFIGFS + libcomposite + usb_f_fs, mount configfs, and a UDC is listed." >&2
  exit 1
fi

cleanup_gadget "$G"
if [ "$CLEAN_ONLY" = 1 ]; then
  echo "Cleaned $G (if present)."
  exit 0
fi

if [ -z "$UDC" ]; then
  UDC=$(list_udc | head -n1 || true)
fi
if [ -z "$UDC" ]; then
  echo "ERROR: no UDC. Pass --udc NAME (from ls /sys/class/udc)." >&2
  exit 1
fi
if [ ! -e "/sys/class/udc/$UDC" ]; then
  echo "ERROR: UDC '$UDC' not found under /sys/class/udc" >&2
  exit 1
fi

echo "Creating gadget $G (UDC=$UDC VID=$VID PID=$PID) ..."
mkdir -p "$G/strings/0x409" "$G/configs/b.1/strings/0x409" "$G/functions/ffs.hdc"
echo "$VID" > "$G/idVendor"
echo "$PID" > "$G/idProduct"
echo 0x0200 > "$G/bcdUSB"
echo "$SERIAL" > "$G/strings/0x409/serialnumber"
echo "OHJS" > "$G/strings/0x409/manufacturer"
echo "HDC Device" > "$G/strings/0x409/product"
echo "hdc" > "$G/configs/b.1/strings/0x409/configuration"
ln -sfn "$G/functions/ffs.hdc" "$G/configs/b.1/"

mkdir -p "$FFS_DIR"
if mountpoint -q "$FFS_DIR" 2>/dev/null; then
  echo "FunctionFS already mounted at $FFS_DIR"
else
  mount -t functionfs hdc "$FFS_DIR"
  echo "Mounted functionfs at $FFS_DIR"
fi

# Do NOT write UDC here if hdcd OSAL binds on sys.usb.ffs.ready — but board script
# may bind now so ep nodes appear after hdcd writes descriptors. Prefer OSAL bind:
# leave UDC empty; print how to bind manually if needed.
# For boards without OSAL gadget bind, operator can: echo UDC > $G/UDC after hdcd -u starts.
if [ "${HDC_USB_BIND_NOW:-0}" = 1 ]; then
  echo "$UDC" > "$G/UDC"
  echo "Bound UDC now: $(cat "$G/UDC")"
else
  echo "UDC not bound yet (hdcd OSAL will bind when ffs ready if HDC_OSAL_USB_GADGET is set)."
  echo "Manual bind: echo $UDC > $G/UDC"
fi

cat <<NEXT

[OK] Gadget ready (FunctionFS mounted; UDC=${HDC_USB_BIND_NOW:-0}).

Next step — start hdcd in USB mode (do not forget developermode / secure=0 on debug images):

  export HDC_OSAL_USB_GADGET=$G
  export HDC_OSAL_USB_UDC=$UDC
  # optional: HDC_OSAL_USB_FFS_BASE=$FFS_DIR
  hdcd -u -l4

Or one-liner:

  HDC_OSAL_USB_GADGET=$G HDC_OSAL_USB_UDC=$UDC hdcd -u -l4

Cleanup later:

  $(basename "$0") --gadget $GNAME --clean

PLACEHOLDER VID:PID $VID:$PID — replace with board-assigned IDs for production.
NEXT
