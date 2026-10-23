# CHANGELOG — `ohjs/6.1-lite` (hand-backport toward v5.0.3)

**Branch:** `ohjs/6.1-lite` @ tip **`df0e5c3`** (and later tips on this doc’s commit)  
**Upstream base:** `51794b3` = OpenHarmony-v6.1-LTS  
**Hand-port target:** OpenHarmony-**v5.0.3**-Release (`3575a53` per `PORT.md`)  
**Authoring rule:** new code under `lite/`; upstream `src/` only via `#ifdef HDC_LITE_OSAL`.

This file is organized **by theme** for Sam’s manual backport. Per-commit detail and v5.0.3 risk notes live in [`../PORT.md`](../PORT.md) (§1–§18).
**Concrete file/diff checklist + order:** [`BACKPORT-v5.0.3.md`](BACKPORT-v5.0.3.md). Protocol for IDE/全栈: [`IDE-CONTRACT.md`](IDE-CONTRACT.md). JS debug research: [`JS-DEBUG.md`](JS-DEBUG.md).

---

## What is portable vs LoongArch64 / musl-specific

| Portable (copy / re-apply on v5 with care) | LA64 / musl / this board lab–specific |
|---|---|
| OSAL API + Linux file-KV Param, re-exec Service, FFS UDC bind | `lite/toolchain/ohos-loongarch64.cmake`, static musl **loongarch64** link |
| `#ifdef HDC_LITE_OSAL` hooks in `main.cpp` / `system_depend.cpp` / `daemon_unity.cpp` / `usb_ffs.h` | qemu-**loongarch64** user IDE env (`run-qemu-hdcd.sh`) |
| hilog → hilogcat fallback | Prebuilt `hdcd.stripped` / host `hdc-linux-x86_64` in board package |
| USB FunctionFS + configfs gadget scripts (any UDC) | dummy_hcd QEMU USB e2e VM; placeholder VID:PID `0x12d1:0x5000` |
| IDE-CONTRACT ports/paths/`__RC`/bm-aa | ACE/jerry **la64** debug `.so` under `b/acelite-la64` |
| board-check / abi-compare / pack-debug-libs / from-board-results (scripts) | Board ABI YES/NO vs those la64 debug libs |
| `setup-usb-gadget.sh`, host hdc docs | Shipping Linux host bin only (no Windows `hdc.exe`) |

v5.0.3 CMake must **drop** 6.1-only sources (`memory_pool`, SSL, heartbeat, …) — see `PORT.md` §1.

---

## 1. OSAL layer

**PORT.md:** §1–§4, §7 · **Commits:** `ccacfcc` → `a7b0d52` → `2db6154` → `50da97a` → `bb0a920`

- Skeleton: Param / Service / USB / PTY / Proc / Priv + shim `parameter.h` / `parameters.h` / `init_reboot.h`.
- **Linux** backend: file-KV (`/etc/hdcd/hdcd.para` + `/data/hdcd/persist.para`), `HDCD_PARAM_*` env override, `restart_self` (+ optional `HDC_OSAL_REEXEC_WRAPPER` for qemu-user).
- **LiteOS-A** backend (`-DHDC_OSAL_TARGET=liteos_a`): **stub/skeleton** — POSIX param include, stub pty/reboot, USB FFS base only (no configfs bind). Compiles with OHOS clang la64; **not** run on real LiteOS-A. Matrix: `lite/osal/README.md`. Default remains **`linux`** (static musl LA64).
- Upstream hooks (medium risk on v5): `system_depend.cpp` Set/GetParameter; `main.cpp` `param_init` + `RestartDaemon`; `daemon_unity.cpp` tmode → `PostStopInstanceMessage(true)`.

**Backport focus:** copy `lite/osal/**`, apply three upstream hunks by hand on v5 indentation/namespaces.

---

## 2. USB / FunctionFS

**PORT.md:** §4–§5, §16 · **Commits:** `50da97a`, `aea2705`, `6dcfcc5`

- On `sys.usb.ffs.ready=1`, OSAL writes UDC into `<gadget>/UDC` (`HDC_OSAL_USB_GADGET` / `HDC_OSAL_USB_UDC` / para keys). Unset gadget → no-op (board init binds).
- `usb_ffs.h`: `USB_FFS_BASE` from `hdc_osal_usb_get_ffs_base()` / `HDC_OSAL_USB_FFS_BASE`.
- Lab: native x86_64 hdcd + QEMU dummy_hcd FunctionFS e2e (enumerate, shell, 20 MB file).
- Board script: `lite/tools/board/setup-usb-gadget.sh` + `README-USB-GADGET.md` — configfs + FunctionFS `/dev/usb-ffs/hdc`, `--dry-run` / `--check` without UDC, default VID:PID `12d1:5000`, prints next `hdcd -u`.

**Backport focus:** OSAL usb + `usb_ffs.h` hook; gadget script is lite-only (portable shell).

---

## 3. hilog → hilogcat

**PORT.md:** §9 · **Commit:** `c143133`

- Small system has `hilogcat` (hilog_lite), not `hilog`.
- `hdc_osal_hilog_cmd()`: prefer `hilog`, else `exec hilogcat`; `-h` → `hilogcat -h`; override `HDC_OSAL_HILOG_CMD`.
- Upstream: `#ifdef HDC_LITE_OSAL` in `GetHiLog` (`daemon_unity.cpp`). Host only forwards `-h`.

**Backport focus:** low-risk hunk on v5 `GetHiLog` + `lite/osal/*/proc.c`.

---

## 4. debug libs / jsdebug / markers

**PORT.md:** §10–§12, §15 · **Commits:** `6d2a9b1`, `9fa05ee`, `bb7cb75`, `aa5559f`, `5c42ddd`

- Docs: `JS-DEBUG.md` (ACE lite + JerryScript debugger).
- G4: jerry debug **only** via hdc `fport` (netns); `verify-jsdebug.sh` (pin plain `jerry-la64`, clear harness env).
- ACE lite patches (scratch tree, not hdc `src/`): runtime wait gate (default **off**) — param / `/data/ohjs/debug.<bundle>` / `ACE_DEBUGGER_WAIT`; bind **127.0.0.1**; `verify-acedbg-gate.sh`, `verify-jsdebug-marker.sh`.
- qemu-ide ensures writable `/data/ohjs` (marker path matches device/IDE).

**Backport focus:** tools/docs/tests under `lite/` only; ACE/jerry patches are separate product trees (la64 builds are lab artifacts).

---

## 5. Board tools & qemu-ide scripts

**PORT.md:** §8, §13–§18 · **Commits:** `ad966bc`, `7e74f38`, `3b83444`, `73ad9b2`, `aa5559f`, `6dcfcc5`, `5c42ddd`, `df0e5c3`

| Area | Paths |
|---|---|
| qemu-ide | `lite/test/qemu-ide/run-qemu-hdcd.sh`, `verify.sh`, `verify-*.sh`, `smoke-stability.sh`, stubs `bm`/`aa`/`hilogcat` |
| Contract regression | `verify-contract.sh` (8710 PASS / 18710 FAIL in start-only; clean `debug.*`); hooked from smoke; `CONTRACT=1` on `verify.sh` |
| Board check | `lite/tools/board/board-check.ps1` — H0 requires host **`Ver: 3.2.0c`** |
| ABI | `abi-compare.sh`/`.ps1`, `unpack-board-results.sh`, `relink-board-needed.sh`, `README-ABI.md` |
| Pack / pipeline | `pack-debug-libs.sh`, `from-board-results.sh` (+ `.ps1`) |
| USB gadget | `setup-usb-gadget.sh`, `README-USB-GADGET.md` |
| Host hdc | `lite/tools/board/host/README.md` — Linux bin in package; Windows = DevEco `sdk\default\openharmony\toolchains\hdc.exe` |

**Backport focus:** copy `lite/tools/board/**` + `lite/test/qemu-ide/**` as-is (scripts). Host/device binaries are build products, not source.

---

## 6. Protocol / ports / IDE-CONTRACT

**PORT.md:** conventions + §16–§17 · **Docs:** `IDE-CONTRACT.md` · **Commits:** `6dcfcc5`, `5c42ddd`, `df0e5c3`

| Role | Port |
|---|---|
| Device hdcd TCP | **8710** |
| Host hdc server (same machine / qemu-ide) | **8711** (`OHOS_HDC_SERVER_PORT`) |
| jsdebug bridge only | **18710** or veth `10.200.1.2:8710` — **not** for G2 deploy |

Paths: `/data/ohjs/`, `/data/ohjs/debug.<bundle>`, `/tmp/ohjs/app.hap`, hilogcap under `/tmp/ohjs` or `/data/ohjs`. Shell: always `; echo __RC=$?`. bm/aa: match stdout text. Clear markers after debug.

Protocol string: **Ver 3.2.0c**, `HDC_MSG_HASH=7fdbc1aa8c5fefaa`.

**Known limitation (upstream, not fixed):** `hdc shell` does not propagate exit status — IDE must use `__RC` (`PORT.md` Known limitations).

---

## Suggested v5.0.3 backport order

1. OSAL skeleton + Linux param/service + upstream `#ifdef` hooks (`PORT.md` §1–§3).  
2. USB FFS base + UDC-on-ready (`§4`); optional gadget script.  
3. hilogcat fallback (`§9`).  
4. Drop 6.1-only CMake sources; smoke TCP.  
5. Bring `lite/docs` (PORT / IDE-CONTRACT / this changelog / JS-DEBUG) and board/qemu scripts as needed for lab — no daemon dependency.

---

## Tip context (as of `df0e5c3`)

- Board prerelease tag: `ohjs-board-2026-10-29` (assets refreshed with docs/tools; Linux host hdc only).  
- IDE repo may carry a synced `docs/IDE-CONTRACT.md` (separate PR; not part of this hdc commit).  
- G2 qemu-ide + contract/stability smokes + G4 jsdebug/marker verifies are the lab gate for this tip.
