/*
 * Copyright (C) 2026 Sam Song
 * Licensed under the Apache License, Version 2.0
 *
 * PTY / shell helpers for hdc shell on toybox/busybox.
 */
#ifndef HDC_OSAL_PTY_H
#define HDC_OSAL_PTY_H

#ifdef __cplusplus
extern "C" {
#endif

/* Open a PTY master; on success write slave path into slave_name (size bytes).
 * Returns master fd or -1. */
int hdc_osal_pty_open(char *slave_name, unsigned size);

/* Preferred shell binary for hdc shell (env HDC_OSAL_SHELL or /bin/sh). */
const char *hdc_osal_shell_path(void);

#ifdef __cplusplus
}
#endif

#endif /* HDC_OSAL_PTY_H */
