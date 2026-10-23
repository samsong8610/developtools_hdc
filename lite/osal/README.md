# hdcd Lite OSAL

Platform abstraction for OpenHarmony lite (Linux musl / LiteOS-A).

| Dir | Role |
|---|---|
| `include/hdc_osal/` | C API: Param / Service / USB / PTY / Proc / Priv |
| `include/shim/` | Drop-in `parameter.h` / `parameters.h` / `init_reboot.h` |
| `linux/` | **Default / production path** — file-KV param, re-exec, configfs UDC bind |
| `liteos_a/` | **Stub / skeleton** — compile-time switch only; not run on LiteOS-A HW yet |

## Selecting the backend

```sh
# Default (omit): Linux musl — static LA64 hdcd for board / qemu-user
cmake … -DHDC_OSAL_TARGET=linux          # or omit; CACHE default is linux

# Stub skeleton (link-check only; ELF is still Linux-ABI without a real LiteOS-A sysroot)
cmake … -DHDC_OSAL_TARGET=liteos_a
# defines: HDC_OSAL_LITEOS_A + __LITEOS_A__ on the OSAL lib
```

Enable OSAL with `-DHDC_LITE_OSAL`. Upstream `src/` only has `#ifdef HDC_LITE_OSAL` hooks.

## Implemented vs stubbed (`liteos_a/`)

| API area | `linux/` | `liteos_a/` |
|---|---|---|
| **Param** (file-KV, `HDCD_PARAM_*`) | Implemented | **POSIX reuse** (`#include "../linux/param.c"`); TODO SysParam if image has it |
| **Service.restart_self** | re-exec + optional `HDC_OSAL_REEXEC_WRAPPER` | `execv` (no qemu wrapper) |
| **Service.reboot / DoReboot** | best-effort | **STUB** `ENOSYS` |
| **USB FFS base** | Implemented | Implemented (env / set) |
| **USB on_ffs_ready → UDC bind** | Implemented (configfs) | **STUB** no-op (no configfs) |
| **PTY** | Implemented | **STUB** `ENOSYS` (one-shot shell via pipes only) |
| **Priv drop/restore** | setuid/setgid | **STUB** no-op (always “root”) |
| **Proc** (exepath, mkdir_p, files, hilog_cmd) | Implemented | POSIX + `/bin/hdcd` fallback; hilog→hilogcat same as linux |

**Must keep working:** default `linux` backend → static loongarch64 `hdcd` (musl) for TCP / board. Changing `liteos_a` stubs must not alter `linux/` behavior.

See also: `lite/PORT.md` §7, `lite/docs/CHANGELOG-ohjs-6.1-lite.md` §1, `lite/docs/BACKPORT-v5.0.3.md`.
