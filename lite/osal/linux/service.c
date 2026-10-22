/*
 * Copyright (C) 2026 Sam Song
 * Licensed under the Apache License, Version 2.0
 */
#include "hdc_osal/service.h"
#include "hdc_osal/proc.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/reboot.h>

int hdc_osal_restart_self(const char *argv0, char *const argv[])
{
    char path[512];
    char *default_argv[3];
    char *const *av = argv;
    const char *wrapper = getenv("HDC_OSAL_REEXEC_WRAPPER");
    char *wrap_av[64];
    int i;

    if (argv0 == NULL || argv0[0] == '\0') {
        if (hdc_osal_exepath(path, sizeof(path)) != 0) {
            return -1;
        }
        argv0 = path;
    }
    if (av == NULL) {
        default_argv[0] = (char *)argv0;
        default_argv[1] = NULL;
        av = default_argv;
    }

    if (wrapper && wrapper[0]) {
        /* exec: wrapper exe [original argv without argv0 duplication] */
        wrap_av[0] = (char *)wrapper;
        wrap_av[1] = (char *)argv0;
        i = 2;
        /* skip guest argv0 if present; pass remaining flags (usually none for service restart) */
        if (av[0] != NULL) {
            char *const *p = av + 1;
            while (*p && i < 62) {
                wrap_av[i++] = *p++;
            }
        }
        wrap_av[i] = NULL;
        execvp(wrapper, wrap_av); /* PATH lookup for qemu-loongarch64 */
        return -1;
    }

    execv(argv0, av);
    return -1;
}

int hdc_osal_reboot(const char *reason)
{
    (void)reason;
    sync();
#ifdef RB_AUTOBOOT
    return reboot(RB_AUTOBOOT);
#else
    return reboot(0x01234567);
#endif
}

int DoReboot(const char *reason)
{
    return hdc_osal_reboot(reason);
}
