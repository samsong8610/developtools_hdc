# hdcd lite port — per-commit change list

Branch `ohjs/6.1-lite` on `samsong8610/developtools_hdc`.
Upstream base: **`51794b3`** (OpenHarmony-v6.1-LTS, see `lite/deps.lock`).
Hand-port target noted below: **OpenHarmony-v5.0.3-Release** (`3575a53`).

Rule: all new code lives under `lite/`. Upstream files are only touched with
`#ifdef HDC_LITE_OSAL` (or `|| defined(HDC_LITE_OSAL)`), so builds without that macro are unchanged.

## Total diff (51794b3..aea2705, 5 code commits; later commits are docs + liteos_a backend, lite/ only)

```
37 files changed, 1395 insertions(+), 6 deletions(-)
upstream files (4):  51 insertions(+), 6 deletions(-)
  src/daemon/daemon_unity.cpp  |  9 ++++++++-
  src/daemon/main.cpp          | 24 ++++++++++++++++++++++++
  src/daemon/system_depend.cpp | 14 +++++++++-----
  src/daemon/usb_ffs.h         | 10 ++++++++++
everything else: new files under lite/
```

## Commits (oldest first)

### 1. `ccacfcc` feat(lite): OSAL skeleton + CMake for static loongarch64 hdcd
- **Files:** new `lite/CMakeLists.txt`, `lite/build.sh`, `lite/deps.lock`, `lite/toolchain/ohos-loongarch64.cmake`,
  `lite/osal/{README.md, include/hdc_osal/*.h, include/shim/{parameter.h,parameters.h,init_reboot.h}, linux/*.c, liteos_a/*.c}`;
  upstream `src/daemon/main.cpp`, `src/daemon/system_depend.cpp`, `src/daemon/usb_ffs.h`.
- **What/why:** adds an OSAL layer (Param/Service/USB/PTY/Proc/Priv) with a Linux implementation and LiteOS-A stubs, so hdcd builds without OH init, syspara, or the GN build.
  The shim headers map OH `parameter.h`/`parameters.h`/`init_reboot.h` onto OSAL.
  Standalone CMake plus a clang toolchain build a static musl loongarch64 hdcd.
  Upstream hooks:
  - `system_depend.cpp`: `HARMONY_PROJECT` guards become `|| HDC_LITE_OSAL` (Set/GetParameter). In lite, `CallDoReboot` calls `DoReboot()`.
  - `usb_ffs.h`: `USB_FFS_BASE` comes from `hdc_osal_usb_get_ffs_base()` (env `HDC_OSAL_USB_FFS_BASE`), so it can be set at runtime.
  - `main.cpp`: OSAL includes (completed in commit 3).
- **v5.0.3 hand-port:** all `lite/` files copy as-is. The CMake source list must drop files that v5.0.3 lacks:
  `common/{memory_pool,connect_validation,hdc_statistic_reporter,server_cmd_log,hdc_ssl,uv_status,heartbeat}.cpp` and `daemon/daemon_ssl.cpp`.
  Also drop the defines `MEMORY_POOL_ENABLE` and `HDC_SUPPORT_ENCRYPT_TCP`.
  Re-check the shims against v5.0.3 includes (e.g. `parameters.h` usage).
  - `usb_ffs.h`: **low risk**, same `constexpr auto USB_FFS_BASE` line (v5 line 32).
  - `system_depend.cpp`: **medium**. v5 has the same guards, but indented in a nested namespace (lines 27/39/53/80) and the file differs by about 87 lines. Apply by hand.

### 2. `a7b0d52` fix(osal): allow HDCD_PARAM_* env override for bringup/smoke
- **Files:** `lite/osal/linux/param.c`.
- **What/why:** an environment variable `HDCD_PARAM_<key with . → _>` takes priority over the file KV. This lets qemu e2e set developermode, port, and mode without a rootfs.
- **v5.0.3:** lite-only, no conflict.

### 3. `2db6154` feat(osal): file-KV Param + tmode restart_self (re-exec)
- **Files:** new `lite/etc/hdcd.para`; `lite/osal/include/hdc_osal/{param.h,service.h}`, `lite/osal/linux/{param.c,service.c}`; upstream `src/daemon/main.cpp`, `src/daemon/daemon_unity.cpp`.
- **What/why:** Param reads defaults from `/etc/hdcd/hdcd.para` and persists to `/data/hdcd/persist.para`. `Service.restart_self` re-execs, optionally through `HDC_OSAL_REEXEC_WRAPPER` (qemu-user).
  Upstream hooks:
  - `main.cpp`: `RestartDaemon()` uses `hdc_osal_restart_self()`. `main()` calls `hdc_osal_param_init()` before the developermode check. Adds `#include <cstdlib>`.
  - `daemon_unity.cpp` `CMD_UNITY_RUNMODE`: on success, `PostStopInstanceMessage(true)`. Stock OH relies on init watching `persist.hdc.*`, and lite has no init. Verified: tmode port 8750→8755.
- **v5.0.3:**
  - `main.cpp` **medium**. v5 `RestartDaemon` (lines 36-43) is a plain `execl` with no `_exit` branch. Wrap the whole body in `#ifdef HDC_LITE_OSAL … #else … #endif`. Put the param_init hook after the `mallopt` block (v5 line 285, before line 289 developermode).
  - `daemon_unity.cpp` **low-medium**. v5 line 415-418 has the identical `SetDeviceRunMode(...)` call, and `SetDeviceRunMode` returns `bool` (v5 line 282). Confirm `daemon->PostStopInstanceMessage` exists in v5 `HdcDaemon`.

### 4. `50da97a` feat(osal): bind configfs gadget UDC on sys.usb.ffs.ready
- **Files:** `lite/osal/include/hdc_osal/usb.h`, `lite/osal/linux/{usb.c,param.c}`.
- **What/why:** replaces the OH init trigger. When hdcd writes the ep0 descriptors and sets `sys.usb.ffs.ready=1`, OSAL writes the UDC name into `<gadget>/UDC`. Config:
  - `HDC_OSAL_USB_GADGET` / `const.hdc.usb.gadget`. Unset means no-op, and the board init binds.
  - `HDC_OSAL_USB_UDC` / `const.hdc.usb.udc`. Defaults to the first entry in `/sys/class/udc`.
  - `sys.usb.ffs.ready` is not persisted.
- **v5.0.3:** lite-only. It relies on the daemon calling `SetDevItem("sys.usb.ffs.ready","1")` in `daemon_usb.cpp` `ConnectEPPoint`; verify the v5 call site is the same.

### 5. `aea2705` test(lite): native hdcd build + QEMU dummy_hcd FunctionFS USB e2e
- **Files:** `lite/CMakeLists.txt` (`HDCD_UVX_DIR`), new `lite/build-native.sh`, `lite/test/usb-vm/{run.sh,guest-init.sh,run-tests.sh,.gitignore}`.
- **What/why:** builds a native x86_64 static hdcd. QEMU (TCG) boots Debian 6.12 with configfs+usb_f_fs+dummy_hcd and placeholder VID:PID 0x12d1:0x5000.
  Passed: enumerate, `list targets` USB Connected, shell, and 20 MB file send/recv.
  `build-native.sh` adds `-include cstdlib`, because upstream `memory_pool.cpp` needs it with libstdc++.
- **v5.0.3:** lite-only, no conflict (the cstdlib workaround may be unnecessary there).

### 6. `146cc07` docs(lite): PORT.md per-commit change list, v5.0.3 notes, known limitations
- **Files:** new `lite/PORT.md`. Docs only.

### 7. feat(osal): LiteOS-A OSAL backend (stubs + POSIX fallbacks), CMake HDC_OSAL_TARGET
- **Files:** `lite/osal/liteos_a/{param,proc,priv,pty,service,usb}.c` (replaces the `#error` placeholders), `lite/CMakeLists.txt`, `lite/osal/README.md`, `lite/PORT.md`.
- **What/why:** `-DHDC_OSAL_TARGET=linux|liteos_a` (default `linux`) picks `osal/<target>/*.c`. `liteos_a` adds the PUBLIC defines `HDC_OSAL_LITEOS_A __LITEOS_A__`.
  Backend behaviour:
  - param: reuses the POSIX file-KV (`#include "../linux/param.c"`).
  - proc: POSIX. `exepath` tries `HDC_OSAL_EXEPATH`, then `/proc/self/exe`, then `/bin/hdcd`.
  - priv: drop/restore root are no-ops.
  - pty: `ENOSYS`.
  - service: `execv` re-exec. Reboot returns `ENOSYS`.
  - usb: configurable FFS base. `on_ffs_ready` is a no-op (no configfs).
- **Verified:** the full daemon compiles and links (static) with the OHOS clang loongarch64 toolchain, build dir `b/liteos_a`. All 25 OSAL symbols are defined.
  The Linux build is byte-identical (sha256 `780d2b3f…63d5`), and TCP e2e passes.
  Upstream `src/` has no `__LITEOS*` conditionals, so the define changes no daemon code.
  **Not run** on LiteOS-A, and it was not built with a real LiteOS-A toolchain/sysroot (the ELF is Linux-ABI).
- **v5.0.3:** lite-only, no conflict.

### 8. test(lite): qemu-user IDE integration env (stub bm/aa/hilogcat)
- **Files:** new `lite/test/qemu-ide/{run-qemu-hdcd.sh,verify.sh,stubs/{bm,aa,hilogcat}}`.
- **What/why:** `run-qemu-hdcd.sh [start|stop|status]` runs the la64 static hdcd under qemu-loongarch64 on TCP 8710. It uses a fake root (`/tmp/ohjs-fakeroot`, param files via `HDC_OSAL_*_PARA`) and stub bm/aa/hilogcat, whose output strings mirror upstream 6.1-LTS, so IDE deploy/start/log flows can be exercised.
  Run the host hdc server on another port (`OHOS_HDC_SERVER_PORT=8711`).
  `verify.sh` covers tconn, shell with `__RC`, file send of a hap, bm set/install/uninstall, aa start/dump/terminate, and hilogcat streaming.
- **v5.0.3:** lite-only.

### 9. feat(osal): `hdc hilog` falls back to hilogcat on small system
- **Files:** upstream `src/daemon/daemon_unity.cpp` (+8, `#ifdef HDC_LITE_OSAL` in `GetHiLog` + include), `lite/osal/include/hdc_osal/proc.h`, `lite/osal/{linux,liteos_a}/proc.c`, `lite/test/qemu-ide/verify.sh`.
- **What/why:** the small system ships `hilogcat` (hilog_lite) but not `hilog`, so upstream `hdc hilog` failed with `hilog: not found`.
  `hdc_osal_hilog_cmd()` returns a sh snippet that runs `hilog` if present, else `exec hilogcat`. `-h` maps to `hilogcat -h`, and env `HDC_OSAL_HILOG_CMD` overrides.
  The host only forwards `-h` (`src/host/translate.cpp` CMDSTR_HILOG), so no other args can be mapped.
  Stop streaming by killing the host client.
- **Verified:** qemu-ide `hdc hilog` streams stub hilogcat lines and `hdc hilog -h` shows the hilogcat usage. TCP e2e passes, and the liteos_a backend still links.
- **v5.0.3:** `GetHiLog` in v5 `daemon_unity.cpp` has the same body (low risk). Copy the hunk.

### 10. docs(lite): JS-DEBUG.md (ace_engine_lite/JerryScript debugger research)
- **Files:** new `lite/docs/JS-DEBUG.md`. Docs only.

### 11. test/tools(lite): G4 JS debug — jerry debugger via hdc fport (netns), ACE lite debug build
- **Files:** `lite/test/qemu-ide/{run-qemu-hdcd.sh (jsdebug mode), verify-jsdebug.sh, build-jerry.sh, sample.js}`, `lite/tools/acelite-debug/{build.sh, ace_engine_lite-debugger.patch, extra-includes.txt}`, `lite/docs/JS-DEBUG.md`.
- **What/why:** an emulated JerryScript debug session goes only through hdcd fport (netns isolation): breakpoint, backtrace and eval pass.
  There is also an experimental loongarch64 ACE lite + jerry debug build: compile/link only, ABI not verified.
- **v5.0.3:** lite-only.

## Known limitations

### `hdc shell` exit code is not propagated (upstream design, not a port bug)
Checked at base `51794b3`:
- `src/common/async_cmd.cpp:60-70` `DoRelease()` only `uv_kill(pid, SIGTERM)`s the child. It never `waitpid`s, so the exit status is never collected. The e2e log shows `DoRelease rc:-3` (ESRCH: the child is already gone).
- `src/common/file_descriptor.cpp:105`: completion fires on pipe EOF, `callbackFinish(ctx, fetalFinish, STRING_EMPTY)`. The bool is an I/O error flag, not an exit status.
- `src/common/async_cmd.cpp:84-92` `FinishShellProc` forwards that flag and the text only.
- `src/daemon/daemon_unity.cpp:109` the result lambda discards its `exitStatus` argument (`int64_t /* exitStatus */`). `AsyncCmdOut(bool finish, string)` (line 50) has no status field, so nothing goes on the wire.
- `src/daemon/shell.cpp:83` the interactive PTY shell `waitpid`s only in `StopTask` after SIGKILL, and ignores `status`.
- `src/host/main.cpp:585-587` the host client runs `RunClientMode(...)` and then `_exit(0)` unconditionally.

**Conclusion:** neither end carries the exit status in either direction, by design. It reproduces identically over qemu-user TCP and over USB with a native hdcd.
**Not fixed in hdcd** (it would also need a host change). The IDE appends `; echo __RC=$?` and parses the marker.

## Port conventions (from handoff)

| Use | Port | Notes |
|---|---|---|
| hdcd TCP (default) | 8710 | product default; IDE uses tcp+8710 for now |
| hdc server (host) | usually 8710, configurable | do not confuse with the device port |
| JerryScript debug | 5001 | |
| tmode switch | any valid port | hdcd persists the port, re-execs, and listens again; reconnect (`tconn`) to the new port |

Firewall: allow device 8710/tcp. Once USB is validated on the board, the IDE default may switch to usb.
