# Board recovery handbook (2K0300 / LoongArch64 lite)

**When HW is OK, start here.** Pure checklist — no new tooling required.  
Package README links here; deeper detail stays in the linked docs.

| Gate | Doc / script |
|---|---|
| Ports / paths / `__RC` | [`IDE-CONTRACT.md`](IDE-CONTRACT.md) |
| Host hdc `Ver: 3.2.0c` | [`../tools/board/host/README.md`](../tools/board/host/README.md) · `check-host-hdc-ver.sh` |
| USB gadget | [`../tools/board/README-USB-GADGET.md`](../tools/board/README-USB-GADGET.md) · `setup-usb-gadget.sh` |
| ABI / debug libs | [`../tools/board/README-ABI.md`](../tools/board/README-ABI.md) · `from-board-results.sh` |
| JS debug (G4) | [`JS-DEBUG.md`](JS-DEBUG.md) |
| qemu lab (no board) | [`../test/qemu-ide/README.md`](../test/qemu-ide/README.md) |
| Full TCP/USB sheet | [BOARD-CHECKLIST.md](BOARD-CHECKLIST.md) (shipped in package) (also `board-check.ps1`) |

Protocol **Ver 3.2.0c** · device TCP **8710** · host server **8711** (`OHOS_HDC_SERVER_PORT`).

---

## 0. Five-minute prep (Sam)

- [ ] Board IP reachable: `ping <IP>` → record `BOARD_IP=________`
- [ ] Host hdc: `hdc -v` → **`Ver: 3.2.0c`** (else run `check-host-hdc-ver.sh` and follow DevEco / `host/hdc-linux-x86_64` hints)
- [ ] Unpack board package; `sha256sum -c SHA256SUMS`
- [ ] Push once (if not already): `hdcd.stripped` → `/data/hdcd/hdcd`, `etc/hdcd.para` → `/etc/hdcd/hdcd.para`
- [ ] Start TCP: on board `hdcd -t` (or init); on host:
  ```bash
  export OHOS_HDC_SERVER_PORT=8711
  hdc -s 127.0.0.1:8711 tconn ${BOARD_IP}:8710
  hdc -s 127.0.0.1:8711 -t ${BOARD_IP}:8710 shell 'echo ok; echo __RC=$?'
  ```
- [ ] **Windows one-click:** `.\board-check.ps1 -Target ${BOARD_IP}:8710` → produces `board-results-*.zip` (preferred return artifact)

---

## 1. USB collection items (read-only first)

Goal: know whether FunctionFS gadget can bind before changing anything.

| ID | Collect (board shell or via hdc) | Pass look like |
|---|---|---|
| U1 | `uname -a`; `cat /proc/device-tree/model 2>/dev/null` | loongarch / 2K0300 identifiable |
| U2 | `ls /sys/class/udc` | ≥1 UDC name (`*.usb` / `dwc*`); **empty = no device controller** |
| U3 | `zcat /proc/config.gz 2>/dev/null \| grep -E 'CONFIG_USB_(CONFIGFS\|FUNCTIONFS\|LIBCOMPOSITE\|DWC)'` or `gunzip -c` | `=y` or `=m` for configfs / ffs / libcomposite |
| U4 | `ls /sys/kernel/config` | configfs mounted |
| U5 | `ls /sys/kernel/config/usb_gadget` | dir exists (may be empty) |
| U6 | `ls -d /dev/usb-ffs /dev/usb-ffs/hdc 2>&1` | after gadget setup; before setup may be missing |
| U7 | `getprop 2>/dev/null \| grep -i usb` or `cat /etc/hdcd/hdcd.para` | hdc USB-related props if any |
| U8 | `lsmod \| grep -E 'usb_f_fs\|libcomposite\|configfs'` | modules if `=m` |

**Scripts:**

```bash
# Dry-run / check without binding UDC (safe):
./setup-usb-gadget.sh --check
./setup-usb-gadget.sh --dry-run
# FSM unit test (no hardware):
./test-usb-gadget-fsm.sh
```

**Return:** paste U1–U8 block **or** rely on `board-check.ps1` zip (`sysinfo/`, USB section).  
If U2 empty → stop USB path; stay on **TCP :8710** until OTG/device mode is fixed.

Placeholder VID:PID for lab gadget: **`12d1:5000`** (see README-USB-GADGET). After bind: `hdcd -u` (device) + host USB hdc.

Full sheet: package **BOARD-CHECKLIST.md §6**.

---

## 2. ABI zip flow (ACE / jerry debug libs)

Goal: decide YES / CONDITIONAL / NO before swapping on-board `.so`.

| Step | Action |
|---|---|
| 1 | On Windows/Linux after TCP OK: run `board-check.ps1` **or** manually `hdc file recv` ACE/jerry libs into `libs/` |
| 2 | Zip → `board-results-<ts>.zip` (script does this) → send to build host |
| 3 | `./from-board-results.sh board-results-*.zip` (or `.ps1`) → unpack → `abi-compare` → optional `BOARD_NEEDED=… ./relink-board-needed.sh` → `pack-debug-libs.sh` |
| 4 | Verdict in `abi-report.md` / `.json` |
| 5 | Only on **YES** (or CONDITIONAL-after-relink): use `debug-libs-*.zip` + print-only `swap-libs.ps1` (`-Execute` required for writes) |

```bash
./from-board-results.sh ~/Downloads/board-results-XXXX.zip
# Offline compare only:
./unpack-board-results.sh board-results-XXXX.zip
./abi-compare.sh --board-libs <unpacked>/libs --debug-libs <acelite-la64 out>
```

One-pager: **README-ABI.md**. Do **not** remount/swap until verdict is YES.

---

## 3. G2 / G4 use-case entry points

### G2 — deploy / launch / log (TCP product path)

| UC | Entry | Expect |
|---|---|---|
| G2-tconn | `hdc -s 127.0.0.1:8711 tconn <IP>:8710` | `Connect OK` |
| G2-shell | `hdc -t <IP>:8710 shell 'echo hi; echo __RC=$?'` | `__RC=0` |
| G2-file | `file send app.hap /tmp/ohjs/app.hap` | `FileTransfer finish` |
| G2-bm-aa | `bm install` / `aa start` via shell | stdout matchers ([IDE-CONTRACT](IDE-CONTRACT.md) §3) |
| G2-hilog | `hilogcat` pid-file lifecycle under `/tmp/ohjs` | capture app log |
| G2-contract | `verify-ide-contract-oneshot.sh` (qemu) or board-check | ports/paths/marker |

**Do not** use port **18710** for G2. Marker clean before deploy: `rm -f /data/ohjs/debug.*`.

### G4 — JS debug (fport / jerry / ACE gate)

| UC | Entry | Expect |
|---|---|---|
| G4-fport | `hdc fport tcp:<host> tcp:5001` then IDE attach | `Forwardport result:OK` |
| G4-jerry-qemu | `run-qemu-hdcd.sh jsdebug` + `verify-jsdebug.sh` | debugger session via fport (not raw 18710 for deploy) |
| G4-marker | `/data/ohjs/debug.<bundle>` + `verify-jsdebug-marker.sh` | wait-with-marker / no-wait-without |
| G4-ace-gate | `verify-acedbg-gate.sh` | env / flag-dir / bind sources |

Research + board caveats: **JS-DEBUG.md**. On real board, confirm jerry/ACE debug `.so` ABI (§2) before relying on G4.

### qemu (no board) smoke order

```bash
lite/test/qemu-ide/run-qemu-hdcd.sh start
lite/test/qemu-ide/verify.sh                  # G2 stubs
lite/test/qemu-ide/verify-ide-contract-oneshot.sh
lite/test/qemu-ide/smoke-qemu-edges.sh
N=20 lite/test/qemu-ide/soak-ide-contract.sh
# G4 when jerry built:
lite/test/qemu-ide/verify-jsdebug.sh
lite/test/qemu-ide/verify-jsdebug-marker.sh
```

---

## 4. Suggested first-hour order (HW OK)

1. §0 prep + TCP shell `__RC`  
2. `board-check.ps1` → zip back  
3. §1 USB U1–U8 (read-only); only then `setup-usb-gadget.sh`  
4. §2 ABI zip → verdict before any `.so` swap  
5. G2 UCs on board; G4 only after ABI YES + jerry/ACE plan in JS-DEBUG.md  

**Errors:** [`ide-error-codes.json`](ide-error-codes.json) / [`IDE-ERROR-CODES.md`](IDE-ERROR-CODES.md) (tconn/file/bm/aa/fport).

**Refresh package from tip:** `lite/tools/board/refresh-board-prerelease.sh`

---

## Doc / verify self-check

```bash
lite/tools/board/check-board-recovery-refs.sh
```

Asserts this handbook (and BOARD-CHECKLIST USB U1–U8) still names real verify/board scripts and that package README keeps `BOARD-RECOVERY` / oneshot / soak / edges entry points. CI runs it with the ide-error-codes job.

