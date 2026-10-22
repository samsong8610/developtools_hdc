/*
 * Copyright (C) 2026 Sam Song
 * Licensed under the Apache License, Version 2.0
 */
#include "hdc_osal/usb.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>

#include "hdc_osal/param.h"

static char g_ffs_base[256] = "/dev/usb-ffs/";

void hdc_osal_usb_set_ffs_base(const char *base)
{
    if (base == NULL || base[0] == '\0') {
        return;
    }
    snprintf(g_ffs_base, sizeof(g_ffs_base), "%s", base);
    /* Ensure trailing slash for join with function name. */
    size_t n = strlen(g_ffs_base);
    if (n > 0 && g_ffs_base[n - 1] != '/' && n + 1 < sizeof(g_ffs_base)) {
        g_ffs_base[n] = '/';
        g_ffs_base[n + 1] = '\0';
    }
}

const char *hdc_osal_usb_get_ffs_base(void)
{
    const char *env = getenv("HDC_OSAL_USB_FFS_BASE");
    if (env != NULL && env[0] != '\0') {
        return env;
    }
    return g_ffs_base;
}

static void cfg_value(const char *env, const char *key, char *out, size_t len)
{
    const char *e = getenv(env);
    out[0] = '\0';
    if (e != NULL && e[0] != '\0') {
        snprintf(out, len, "%s", e);
        return;
    }
    GetParameter(key, "", out, (unsigned int)len);
}

static int first_udc(char *out, size_t len)
{
    DIR *d = opendir("/sys/class/udc");
    struct dirent *e;
    if (d == NULL) {
        return -1;
    }
    out[0] = '\0';
    while ((e = readdir(d)) != NULL) {
        if (e->d_name[0] != '.') {
            snprintf(out, len, "%s", e->d_name);
            break;
        }
    }
    closedir(d);
    return out[0] ? 0 : -1;
}

int hdc_osal_usb_on_ffs_ready(void)
{
    char gadget[256];
    char udc[128];
    char path[320];
    char cur[128] = {0};
    int fd;
    ssize_t n;

    cfg_value("HDC_OSAL_USB_GADGET", "const.hdc.usb.gadget", gadget, sizeof(gadget));
    if (gadget[0] == '\0') {
        return 0;
    }
    cfg_value("HDC_OSAL_USB_UDC", "const.hdc.usb.udc", udc, sizeof(udc));
    if (udc[0] == '\0' && first_udc(udc, sizeof(udc)) != 0) {
        fprintf(stderr, "hdc_osal_usb: no UDC in /sys/class/udc\n");
        return -1;
    }
    snprintf(path, sizeof(path), "%s/UDC", gadget);
    fd = open(path, O_RDONLY);
    if (fd >= 0) {
        n = read(fd, cur, sizeof(cur) - 1);
        close(fd);
        if (n > 0 && cur[0] != '\n') {
            return 0; /* already bound */
        }
    }
    fd = open(path, O_WRONLY);
    if (fd < 0) {
        fprintf(stderr, "hdc_osal_usb: open %s: %s\n", path, strerror(errno));
        return -1;
    }
    n = write(fd, udc, strlen(udc));
    close(fd);
    if (n < 0) {
        fprintf(stderr, "hdc_osal_usb: bind %s -> %s: %s\n", udc, path, strerror(errno));
        return -1;
    }
    return 0;
}
