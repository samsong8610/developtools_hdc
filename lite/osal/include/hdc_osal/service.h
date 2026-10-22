/*
 * Copyright (C) 2026 Sam Song
 * Licensed under the Apache License, Version 2.0
 *
 * restart_self: re-exec current binary.
 * If HDC_OSAL_REEXEC_WRAPPER is set (e.g. qemu-loongarch64), exec
 *   $WRAPPER <exe> [args...]
 * so user-mode qemu can restart a cross-arch binary.
 */
#ifndef HDC_OSAL_SERVICE_H
#define HDC_OSAL_SERVICE_H

#ifdef __cplusplus
extern "C" {
#endif

int hdc_osal_restart_self(const char *argv0, char *const argv[]);
int hdc_osal_reboot(const char *reason);
int DoReboot(const char *reason);

#ifdef __cplusplus
}
#endif

#endif /* HDC_OSAL_SERVICE_H */
