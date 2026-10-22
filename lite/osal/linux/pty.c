#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
/*
 * Copyright (C) 2026 Sam Song
 * Licensed under the Apache License, Version 2.0
 */
#include "hdc_osal/pty.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int hdc_osal_pty_open(char *slave_name, unsigned size)
{
    int master = posix_openpt(O_RDWR | O_NOCTTY);
    if (master < 0) {
        return -1;
    }
    if (grantpt(master) != 0 || unlockpt(master) != 0) {
        close(master);
        return -1;
    }
    if (slave_name != NULL && size > 0) {
        if (ptsname_r(master, slave_name, size) != 0) {
            close(master);
            return -1;
        }
    }
    return master;
}

const char *hdc_osal_shell_path(void)
{
    const char *env = getenv("HDC_OSAL_SHELL");
    if (env != NULL && env[0] != '\0') {
        return env;
    }
    if (access("/bin/sh", X_OK) == 0) {
        return "/bin/sh";
    }
    if (access("/system/bin/sh", X_OK) == 0) {
        return "/system/bin/sh";
    }
    return "/bin/sh";
}
