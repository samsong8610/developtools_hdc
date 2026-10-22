/*
 * Copyright (C) 2026 Sam Song
 * Licensed under the Apache License, Version 2.0
 *
 * Privilege helpers (setuid/setgid drop / restore) for lite devices
 * without SELinux / OH privilege frameworks.
 */
#ifndef HDC_OSAL_PRIV_H
#define HDC_OSAL_PRIV_H

#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

int hdc_osal_drop_root(uid_t uid, gid_t gid);
int hdc_osal_restore_root(void);
int hdc_osal_is_root(void);

#ifdef __cplusplus
}
#endif

#endif /* HDC_OSAL_PRIV_H */
