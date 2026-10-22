/*
 * Copyright (C) 2026 Sam Song
 * Licensed under the Apache License, Version 2.0
 */
#include "hdc_osal/priv.h"

#include <unistd.h>

int hdc_osal_drop_root(uid_t uid, gid_t gid)
{
    if (setgid(gid) != 0) {
        return -1;
    }
    if (setuid(uid) != 0) {
        return -1;
    }
    return 0;
}

int hdc_osal_restore_root(void)
{
    /* Only works if process retained CAP_SETUID; lite often cannot. */
    if (seteuid(0) != 0) {
        return -1;
    }
    if (setegid(0) != 0) {
        return -1;
    }
    return 0;
}

int hdc_osal_is_root(void)
{
    return (geteuid() == 0) ? 1 : 0;
}
