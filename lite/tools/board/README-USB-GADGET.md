# USB gadget + FunctionFS (board)

English snippet for operators. Script: `setup-usb-gadget.sh`.

## Prerequisites

- Kernel: `configfs`, `libcomposite`, `usb_f_fs` (and a device UDC listed in `/sys/class/udc`).
- Run on the **device** (root). Host PCs without a UDC: use `--check` / `--dry-run` only.

## Quick start

```sh
# Inspect (safe)
./setup-usb-gadget.sh --check
./setup-usb-gadget.sh --dry-run

# Create gadget (default VID:PID 0x12d1:0x5000 PLACEHOLDER), mount FunctionFS at /dev/usb-ffs/hdc
./setup-usb-gadget.sh --udc "$(ls /sys/class/udc | head -1)" --serial OHJSBOARD01

# Start hdcd USB mode (OSAL binds UDC when ffs ready)
HDC_OSAL_USB_GADGET=/sys/kernel/config/usb_gadget/hdc \
HDC_OSAL_USB_UDC="$(ls /sys/class/udc | head -1)" \
  hdcd -u -l4
```

## Parameters

| Flag / env | Default | Meaning |
|---|---|---|
| `--udc` / `HDC_USB_UDC` | first `/sys/class/udc` | Device controller name |
| `--vid` / `HDC_USB_VID` | `0x12d1` | Placeholder vendor ID |
| `--pid` / `HDC_USB_PID` | `0x5000` | Placeholder product ID |
| `--serial` / `HDC_USB_SERIAL` | `OHJS0001` | USB serial string |
| `--gadget` | `hdc` | configfs gadget directory name |
| `--ffs-dir` | `/dev/usb-ffs/hdc` | FunctionFS mount point |
| `--clean` | | Tear down same gadget + umount FFS |
| `HDC_USB_BIND_NOW=1` | off | Write UDC immediately (else let hdcd OSAL bind) |

Idempotent: re-running cleans the named gadget first. Does **not** start `hdcd`.
