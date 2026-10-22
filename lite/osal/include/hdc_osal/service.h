/*
 * Copyright (C) 2026 Sam Song
 * Licensed under the Apache License, Version 2.0
 *
 * Service lifecycle: self-restart (re-exec) and reboot.
 */
#ifndef HDC_OSAL_SERVICE_H
#define HDC_OSAL_SERVICE_H

#ifdef __cplusplus
extern "C" {
#endif

/* Re-exec current binary (hdcd restart_self). argv0 may be NULL → /proc/self/exe. */
int hdc_osal_restart_self(const char *argv0, char *const argv[]);

/* Soft reboot request. reason e.g. "reboot" or "reboot,updater". */
int hdc_osal_reboot(const char *reason);

/* Compatibility: OpenHarmony init_reboot.h */
int DoReboot(const char *reason);

#ifdef __cplusplus
}
#endif

#endif /* HDC_OSAL_SERVICE_H */
