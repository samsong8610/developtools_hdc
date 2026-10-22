/*
 * Copyright (C) 2026 Sam Song
 * Licensed under the Apache License, Version 2.0
 *
 * LiteOS-A OSAL (stub/POSIX fallback). Selected by -DHDC_OSAL_TARGET=liteos_a.
 * Compile/link-verified only; NOT run on LiteOS-A hardware.
 */
#include "hdc_osal/pty.h"

#include <errno.h>
#include <stdlib.h>
#include <unistd.h>

/* No PTY on LiteOS-A: interactive shell unsupported; one-shot shell uses pipes. */
int hdc_osal_pty_open(char *slave_name, unsigned size)
{
    if (slave_name != NULL && size > 0) {
        slave_name[0] = '\0';
    }
    errno = ENOSYS;
    return -1;
}

const char *hdc_osal_shell_path(void)
{
    const char *env = getenv("HDC_OSAL_SHELL");
    if (env != NULL && env[0] != '\0') {
        return env;
    }
    return "/bin/sh"; /* LiteOS-A toybox/mksh */
}
