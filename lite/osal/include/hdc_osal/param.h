/*
 * Copyright (C) 2026 Sam Song
 * Licensed under the Apache License, Version 2.0
 *
 * File-KV parameters:
 *   defaults  /etc/hdcd/hdcd.para     (read-only baseline)
 *   persist   /data/hdcd/persist.para (atomic read-modify-write)
 * Override paths via HDC_OSAL_DEFAULT_PARA / HDC_OSAL_PERSIST_PARA
 * or hdc_osal_param_set_paths(). Env HDCD_PARAM_<key> still wins for bringup.
 */
#ifndef HDC_OSAL_PARAM_H
#define HDC_OSAL_PARAM_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int GetParameter(const char *key, const char *def, char *value, unsigned int len);
int SetParameter(const char *key, const char *value);
unsigned int GetUintParameter(const char *key, unsigned int def);
int WatchParameter(const char *keyprefix, void (*callback)(const char *, const char *, void *), void *context);

void hdc_osal_param_set_paths(const char *default_para, const char *persist_para);
const char *hdc_osal_param_default_path(void);
const char *hdc_osal_param_persist_path(void);
/* Ensure parent dirs exist; optionally seed defaults file from built-in template. */
int hdc_osal_param_init(void);

/* legacy aliases used by early stubs */
void hdc_osal_param_set_dir(const char *dir);
const char *hdc_osal_param_get_dir(void);

#ifdef __cplusplus
}
#endif

#endif /* HDC_OSAL_PARAM_H */
