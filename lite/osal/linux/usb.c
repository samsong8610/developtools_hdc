/*
 * Copyright (C) 2026 Sam Song
 * Licensed under the Apache License, Version 2.0
 */
#include "hdc_osal/usb.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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
