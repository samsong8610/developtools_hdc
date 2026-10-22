/*
 * Copyright (C) 2026 Sam Song
 * Licensed under the Apache License, Version 2.0
 */
#include "hdc_osal/param.h"
#include "hdc_osal/proc.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#ifndef HDC_OSAL_PARAM_DIR_DEFAULT
#define HDC_OSAL_PARAM_DIR_DEFAULT "/data/local/hdc/param"
#endif

static char g_param_dir[512] = HDC_OSAL_PARAM_DIR_DEFAULT;

void hdc_osal_param_set_dir(const char *dir)
{
    if (dir == NULL || dir[0] == '\0') {
        return;
    }
    snprintf(g_param_dir, sizeof(g_param_dir), "%s", dir);
}

const char *hdc_osal_param_get_dir(void)
{
    return g_param_dir;
}

static void key_to_path(const char *key, char *out, size_t out_len)
{
    /* Flatten "a.b.c" → "a.b.c" file under param dir (dots kept; '/' → '_'). */
    char safe[256];
    size_t i;
    for (i = 0; key[i] != '\0' && i + 1 < sizeof(safe); ++i) {
        char c = key[i];
        safe[i] = (c == '/' || c == '\\') ? '_' : c;
    }
    safe[i] = '\0';
    snprintf(out, out_len, "%s/%s", g_param_dir, safe);
}

int GetParameter(const char *key, const char *def, char *value, unsigned int len)
{
    char path[768];
    char envname[320];
    const char *env;
    size_t el;
    int n;
    if (key == NULL || value == NULL || len == 0) {
        return -1;
    }
    /* Bringup override: HDCD_PARAM_<key with '.' -> '_'> */
    el = 0;
    memcpy(envname, "HDCD_PARAM_", 11); el = 11;
    for (const char *p = key; *p && el + 1 < sizeof(envname); ++p) {
        envname[el++] = (*p == '.') ? '_' : *p;
    }
    envname[el] = '\0';
    env = getenv(envname);
    if (env != NULL) {
        snprintf(value, len, "%s", env);
        return (int)strlen(value);
    }
    key_to_path(key, path, sizeof(path));
    n = hdc_osal_read_file(path, value, len);
    if (n < 0) {
        if (def != NULL) {
            snprintf(value, len, "%s", def);
            return (int)strlen(value);
        }
        value[0] = '\0';
        return -1;
    }
    /* Trim trailing newline */
    while (n > 0 && (value[n - 1] == '\n' || value[n - 1] == '\r')) {
        value[--n] = '\0';
    }
    return n;
}

int SetParameter(const char *key, const char *value)
{
    char path[768];
    if (key == NULL || value == NULL) {
        return -1;
    }
    hdc_osal_mkdir_p(g_param_dir);
    key_to_path(key, path, sizeof(path));
    return hdc_osal_write_file(path, value, (unsigned)strlen(value));
}

unsigned int GetUintParameter(const char *key, unsigned int def)
{
    char buf[64] = {0};
    char *end = NULL;
    unsigned long v;
    if (GetParameter(key, NULL, buf, sizeof(buf)) <= 0) {
        return def;
    }
    errno = 0;
    v = strtoul(buf, &end, 0);
    if (errno != 0 || end == buf) {
        return def;
    }
    return (unsigned int)v;
}

int WatchParameter(const char *keyprefix, void (*callback)(const char *, const char *, void *), void *context)
{
    (void)keyprefix;
    (void)callback;
    (void)context;
    /* Lite: no param service; watchers are no-ops (JDWP optional). */
    return 0;
}
