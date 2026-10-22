/*
 * Copyright (C) 2026 Sam Song
 * Licensed under the Apache License, Version 2.0
 *
 * Process / file helpers (exe path, mkdir -p, etc.).
 */
#ifndef HDC_OSAL_PROC_H
#define HDC_OSAL_PROC_H

#ifdef __cplusplus
extern "C" {
#endif

/* Fill buf with absolute path of current executable. Returns 0 on success. */
int hdc_osal_exepath(char *buf, unsigned size);

/* Recursively create directory (mode 0755). Returns 0 on success. */
int hdc_osal_mkdir_p(const char *path);

/* Read entire small file into buf; returns bytes read or -1. */
int hdc_osal_read_file(const char *path, char *buf, unsigned size);

/* Write value atomically (tmp + rename). Returns 0 on success. */
int hdc_osal_write_file(const char *path, const char *data, unsigned len);

#ifdef __cplusplus
}
#endif

#endif /* HDC_OSAL_PROC_H */
