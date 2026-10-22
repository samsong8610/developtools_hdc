# hdcd lite port — per-commit change list

Branch `ohjs/6.1-lite` on `samsong8610/developtools_hdc`.
Upstream base: **`51794b3`** (OpenHarmony-v6.1-LTS, see `lite/deps.lock`).
Hand-port target noted below: **OpenHarmony-v5.0.3-Release** (`3575a53`).

Rule: all new code lives under `lite/`. Upstream files are only touched with
`#ifdef HDC_LITE_OSAL` (or `|| defined(HDC_LITE_OSAL)`), so builds without that macro are unchanged.

## Total diff (51794b3..aea2705, 5 commits)

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
