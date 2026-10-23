# LiteOS-A OSAL — stub / skeleton

Selected only with `-DHDC_OSAL_TARGET=liteos_a` (CMake default remains **`linux`**).

| Status | Meaning |
|---|---|
| Compile/link-checked | Full static LA64 daemon links with OHOS clang; symbols defined |
| **Not** hardware-validated | No real LiteOS-A sysroot/toolchain in this lab; ELF is Linux-ABI |
| Ready for later port | Replace STUB/`ENOSYS`/no-op sites when a LiteOS-A image + headers arrive |

Per-file notes are in each `*.c` header (`TODO(liteos_a)`). Matrix: [`../README.md`](../README.md).
