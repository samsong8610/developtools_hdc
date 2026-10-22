# hdcd Lite OSAL

Platform abstraction for OpenHarmony lite (Linux musl / LiteOS-A).

| Dir | Role |
|---|---|
| `include/hdc_osal/` | C API: Param / Service / USB / PTY / Proc / Priv |
| `include/shim/` | Drop-in `parameter.h` / `parameters.h` / `init_reboot.h` |
| `linux/` | File-KV param, re-exec, configurable FunctionFS base |
| `liteos_a/` | Stubs (compile error if selected) |

Enable with `-DHDC_LITE_OSAL`. Upstream `src/` only has `#ifdef HDC_LITE_OSAL` hooks.
