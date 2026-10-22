/*
 * Copyright (C) 2026 Sam Song
 * Licensed under the Apache License, Version 2.0
 */
#include "hdc_osal/param.h"
#include "hdc_osal/proc.h"
#include "hdc_osal/usb.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#ifndef HDC_OSAL_DEFAULT_PARA_PATH
#define HDC_OSAL_DEFAULT_PARA_PATH "/etc/hdcd/hdcd.para"
#endif
#ifndef HDC_OSAL_PERSIST_PARA_PATH
#define HDC_OSAL_PERSIST_PARA_PATH "/data/hdcd/persist.para"
#endif

static char g_default_path[512] = HDC_OSAL_DEFAULT_PARA_PATH;
static char g_persist_path[512] = HDC_OSAL_PERSIST_PARA_PATH;
static int g_inited = 0;

/* Built-in defaults when /etc file is absent (debug firmware). */
static const char BUILTIN_DEFAULTS[] =
    "# hdcd lite default parameters (debug)\n"
    "const.security.developermode.state=true\n"
    "const.hdc.secure=0\n"
    "const.debuggable=1\n"
    "persist.hdc.root=1\n"
    "persist.hdc.mode=tcp\n"
    "persist.hdc.mode.tcp=enable\n"
    "persist.hdc.port=8710\n";

static void resolve_paths_from_env(void)
{
    const char *d = getenv("HDC_OSAL_DEFAULT_PARA");
    const char *p = getenv("HDC_OSAL_PERSIST_PARA");
    if (d && d[0]) {
        snprintf(g_default_path, sizeof(g_default_path), "%s", d);
    }
    if (p && p[0]) {
        snprintf(g_persist_path, sizeof(g_persist_path), "%s", p);
    }
}

void hdc_osal_param_set_paths(const char *default_para, const char *persist_para)
{
    if (default_para && default_para[0]) {
        snprintf(g_default_path, sizeof(g_default_path), "%s", default_para);
    }
    if (persist_para && persist_para[0]) {
        snprintf(g_persist_path, sizeof(g_persist_path), "%s", persist_para);
    }
}

const char *hdc_osal_param_default_path(void)
{
    resolve_paths_from_env();
    return g_default_path;
}

const char *hdc_osal_param_persist_path(void)
{
    resolve_paths_from_env();
    return g_persist_path;
}

void hdc_osal_param_set_dir(const char *dir)
{
    /* legacy: treat as persist directory parent */
    if (!dir || !dir[0]) {
        return;
    }
    snprintf(g_persist_path, sizeof(g_persist_path), "%s/persist.para", dir);
}

const char *hdc_osal_param_get_dir(void)
{
    return g_persist_path;
}

static void dirname_of(const char *path, char *out, size_t out_len)
{
    size_t n = strlen(path);
    while (n > 0 && path[n - 1] != '/') {
        --n;
    }
    if (n == 0) {
        snprintf(out, out_len, ".");
        return;
    }
    if (n >= out_len) {
        n = out_len - 1;
    }
    memcpy(out, path, n);
    out[n] = '\0';
}

int hdc_osal_param_init(void)
{
    char dir[512];
    resolve_paths_from_env();
    dirname_of(g_default_path, dir, sizeof(dir));
    hdc_osal_mkdir_p(dir);
    dirname_of(g_persist_path, dir, sizeof(dir));
    hdc_osal_mkdir_p(dir);
    if (access(g_default_path, R_OK) != 0) {
        hdc_osal_write_file(g_default_path, BUILTIN_DEFAULTS, (unsigned)strlen(BUILTIN_DEFAULTS));
    }
    if (access(g_persist_path, F_OK) != 0) {
        hdc_osal_write_file(g_persist_path, "# hdcd persist\n", 15);
    }
    g_inited = 1;
    return 0;
}

static int lookup_in_file(const char *path, const char *key, char *value, unsigned int len)
{
    FILE *fp;
    char line[1024];
    size_t klen;
    if (!path || !key || !value || len == 0) {
        return -1;
    }
    fp = fopen(path, "r");
    if (!fp) {
        return -1;
    }
    klen = strlen(key);
    while (fgets(line, sizeof(line), fp)) {
        char *p = line;
        char *eq;
        size_t vlen;
        while (*p == ' ' || *p == '\t') {
            ++p;
        }
        if (*p == '#' || *p == '\n' || *p == '\0') {
            continue;
        }
        eq = strchr(p, '=');
        if (!eq) {
            continue;
        }
        if ((size_t)(eq - p) != klen || strncmp(p, key, klen) != 0) {
            continue;
        }
        ++eq;
        /* trim trailing newline/CR */
        vlen = strlen(eq);
        while (vlen > 0 && (eq[vlen - 1] == '\n' || eq[vlen - 1] == '\r')) {
            eq[--vlen] = '\0';
        }
        snprintf(value, len, "%s", eq);
        fclose(fp);
        return (int)strlen(value);
    }
    fclose(fp);
    return -1;
}

static int env_override(const char *key, char *value, unsigned int len)
{
    char envname[320];
    size_t el = 0;
    const char *env;
    memcpy(envname, "HDCD_PARAM_", 11);
    el = 11;
    for (const char *p = key; *p && el + 1 < sizeof(envname); ++p) {
        envname[el++] = (*p == '.') ? '_' : *p;
    }
    envname[el] = '\0';
    env = getenv(envname);
    if (!env) {
        return -1;
    }
    snprintf(value, len, "%s", env);
    return (int)strlen(value);
}

int GetParameter(const char *key, const char *def, char *value, unsigned int len)
{
    int n;
    if (!key || !value || len == 0) {
        return -1;
    }
    if (!g_inited) {
        hdc_osal_param_init();
    }
    n = env_override(key, value, len);
    if (n >= 0) {
        return n;
    }
    n = lookup_in_file(g_persist_path, key, value, len);
    if (n >= 0) {
        return n;
    }
    n = lookup_in_file(g_default_path, key, value, len);
    if (n >= 0) {
        return n;
    }
    if (def) {
        snprintf(value, len, "%s", def);
        return (int)strlen(value);
    }
    value[0] = '\0';
    return -1;
}

int SetParameter(const char *key, const char *value)
{
    char *buf = NULL;
    size_t cap = 0;
    size_t used = 0;
    FILE *fp;
    char line[1024];
    int found = 0;
    size_t klen;
    char dir[512];

    if (!key || !value) {
        return -1;
    }
    if (!g_inited) {
        hdc_osal_param_init();
    }
    if (strcmp(key, "sys.usb.ffs.ready") == 0) {
        /* Volatile trigger (OH init: bind UDC). Do not persist. */
        if (strcmp(value, "1") == 0) {
            return hdc_osal_usb_on_ffs_ready() == 0 ? 0 : -1;
        }
        return 0;
    }
    klen = strlen(key);
    dirname_of(g_persist_path, dir, sizeof(dir));
    hdc_osal_mkdir_p(dir);

    fp = fopen(g_persist_path, "r");
    if (fp) {
        while (fgets(line, sizeof(line), fp)) {
            char *p = line;
            char *eq;
            int is_match = 0;
            while (*p == ' ' || *p == '\t') {
                ++p;
            }
            if (*p != '#' && *p != '\n' && *p != '\0') {
                eq = strchr(p, '=');
                if (eq && (size_t)(eq - p) == klen && strncmp(p, key, klen) == 0) {
                    is_match = 1;
                    found = 1;
                }
            }
            if (is_match) {
                continue; /* drop old value; append fresh below */
            }
            {
                size_t l = strlen(line);
                if (used + l + 1 > cap) {
                    size_t ncap = cap ? cap * 2 : 4096;
                    while (ncap < used + l + 1) {
                        ncap *= 2;
                    }
                    char *nb = (char *)realloc(buf, ncap);
                    if (!nb) {
                        free(buf);
                        fclose(fp);
                        return -1;
                    }
                    buf = nb;
                    cap = ncap;
                }
                memcpy(buf + used, line, l);
                used += l;
            }
        }
        fclose(fp);
    }

    {
        char entry[1100];
        int elen = snprintf(entry, sizeof(entry), "%s=%s\n", key, value);
        if (elen < 0) {
            free(buf);
            return -1;
        }
        if (used + (size_t)elen + 1 > cap) {
            size_t ncap = used + (size_t)elen + 1;
            char *nb = (char *)realloc(buf, ncap);
            if (!nb) {
                free(buf);
                return -1;
            }
            buf = nb;
            cap = ncap;
        }
        memcpy(buf + used, entry, (size_t)elen);
        used += (size_t)elen;
    }
    (void)found;
    if (used == 0) {
        free(buf);
        return hdc_osal_write_file(g_persist_path, "", 0);
    }
    {
        int rc = hdc_osal_write_file(g_persist_path, buf, (unsigned)used);
        free(buf);
        return rc;
    }
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
    return 0;
}
