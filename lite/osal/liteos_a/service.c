/*
 * Copyright (C) 2026 Sam Song
 * Licensed under the Apache License, Version 2.0
 *
 * LiteOS-A OSAL (stub/POSIX fallback). Selected by -DHDC_OSAL_TARGET=liteos_a.
 * Compile/link-verified only; NOT run on LiteOS-A hardware.
 */
#include "hdc_osal/service.h"
#include "hdc_osal/proc.h"

#include <errno.h>
#include <stddef.h>
#include <unistd.h>

int hdc_osal_restart_self(const char *argv0, char *const argv[])
{
    char path[512];
    char *def[2];
    if (argv0 == NULL || argv0[0] == '\0') {
        if (hdc_osal_exepath(path, sizeof(path)) != 0) {
            return -1;
        }
        argv0 = path;
    }
    if (argv == NULL) {
        def[0] = (char *)argv0;
        def[1] = NULL;
        argv = def;
    }
    execv(argv0, argv); /* LiteOS-A supports exec of ELF from fs */
    return -1;
}

int hdc_osal_reboot(const char *reason)
{
    (void)reason;
    errno = ENOSYS; /* TODO(liteos_a): map to system reboot API */
    return -1;
}

int DoReboot(const char *reason)
{
    return hdc_osal_reboot(reason);
}
