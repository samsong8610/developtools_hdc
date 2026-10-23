# USB gadget setup (configfs + FunctionFS)

Board-side helper for hdcd USB (`hdcd -u`). **Runs without a real board** in `--dry-run` / `--check` modes.

## No-board / CI host

```sh
./setup-usb-gadget.sh --dry-run    # prints planned steps; exit 0
./setup-usb-gadget.sh --check      # probes configfs + UDC; exit 1 if missing (expected on laptop/CI)
./setup-usb-gadget.sh --clean      # idempotent remove of named gadget if present
```

Default placeholder VID:PID **`0x12d1:0x5000`** (same as qemu `dummy_hcd` e2e under `lite/test/usb-vm/`).

## On board (or VM with dummy_hcd)

```sh
./setup-usb-gadget.sh --udc <name>           # or HDC_USB_UDC=…
# prints: export HDC_OSAL_USB_GADGET=… ; hdcd -u
```

Env: `HDC_USB_UDC`, `HDC_USB_VID`, `HDC_USB_PID`, `HDC_USB_SERIAL`, `HDC_USB_GADGET`, `HDC_USB_FFS_DIR` (default `/dev/usb-ffs/hdc`).

Requires kernel **configfs** + **usb_f_fs** (+ a UDC). Without them, only dry-run/check are useful — do not treat check MISS as a script bug.

See also: `lite/test/usb-vm/` (QEMU FunctionFS e2e), OSAL `hdc_osal_usb_on_ffs_ready` (linux binds UDC; liteos_a is no-op stub).

## Unit tests (no kernel / no real VID)

```sh
./test-usb-gadget-fsm.sh
# Covers: configfs missing, UDC missing, bind fail, cleanup idempotent,
#         state ABSENT→…→UDC_BOUND under a fake CFG root.
```

Logic lives in `usb-gadget-fsm.sh` (sourced by setup + tests). Placeholder VID:PID is never written to hardware in these tests.
