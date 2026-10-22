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
    if (argv0 == NULL || argv0[0] == '\0') {
        if (hdc_osal_exepath(path, sizeof(path)) != 0) {
            return -1;
        }
        argv0 = path;
    }
    if (av == NULL) {
        default_argv[0] = (char *)"hdcd";
        default_argv[1] = NULL;
        av = default_argv;
    }
    execv(argv0, av);
    /* only reached on failure */
    return -1;
}

int hdc_osal_reboot(const char *reason)
{
    /* Prefer userspace reboot helper if present; else syscall. */
    (void)reason;
    sync();
#ifdef RB_AUTOBOOT
    return reboot(RB_AUTOBOOT);
#else
    return reboot(0x01234567); /* LINUX_REBOOT_CMD_RESTART */
#endif
}

int DoReboot(const char *reason)
{
    return hdc_osal_reboot(reason);
}
