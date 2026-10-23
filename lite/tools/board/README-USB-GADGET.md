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

## Board recovery (U1–U8)

Before binding gadget on hardware, collect read-only probes **U1–U8** in
[`BOARD-RECOVERY.md` §1](../../docs/BOARD-RECOVERY.md#1-usb-collection-items-read-only-first)
(and package `BOARD-CHECKLIST.md` §6). Summary:

| ID | Why it matters for this script / FSM |
|---|---|
| U1 | Board identity (loongarch / 2K0300) |
| U2 | UDC present — empty list → do not bind; FSM stays pre-UDC_BOUND |
| U3 | Kernel `CONFIG_USB_CONFIGFS` / `FUNCTIONFS` / `LIBCOMPOSITE` |
| U4/U5 | configfs + `usb_gadget` writable |
| U6 | `/dev/usb-ffs/hdc` after setup |
| U7 | hdc USB props / `hdcd.para` |
| U8 | modules if built `=m` |

CI: `test-usb-gadget-fsm.sh` (job `usb-gadget-fsm` in `lite-osal.yml`) exercises happy + NEG paths with a fake configfs root — no board required. Cross-check with recovery refs: `check-board-recovery-refs.sh`.
