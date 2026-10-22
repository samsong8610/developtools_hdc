/*
 * Copyright (C) 2026 Sam Song
 * Licensed under the Apache License, Version 2.0
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
void hdc_osal_param_set_dir(const char *dir);
const char *hdc_osal_param_get_dir(void);

#ifdef __cplusplus
}
#endif

#endif /* HDC_OSAL_PARAM_H */
