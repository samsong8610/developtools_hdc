/*
 * Copyright (C) 2026 Sam Song
 * Licensed under the Apache License, Version 2.0
 *
 * LiteOS-A OSAL (stub/POSIX fallback). Selected by -DHDC_OSAL_TARGET=liteos_a.
 * Compile/link-verified only; NOT run on LiteOS-A hardware.
 */
#include "hdc_osal/usb.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char g_ffs_base[256] = "/dev/usb-ffs/";

void hdc_osal_usb_set_ffs_base(const char *base)
{
    size_t n;
    if (base == NULL || base[0] == '\0') {
        return;
    }
    snprintf(g_ffs_base, sizeof(g_ffs_base), "%s", base);
    n = strlen(g_ffs_base);
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

/* No configfs on LiteOS-A; gadget is bound by the kernel USB stack. No-op. */
int hdc_osal_usb_on_ffs_ready(void)
{
    return 0;
}
