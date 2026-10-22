/*
 * Copyright (C) 2026 Sam Song
 * Licensed under the Apache License, Version 2.0
 *
 * LiteOS-A OSAL (stub/POSIX fallback). Selected by -DHDC_OSAL_TARGET=liteos_a.
 * Compile/link-verified only; NOT run on LiteOS-A hardware.
 */
#include "hdc_osal/priv.h"

#include <errno.h>
#include <unistd.h>

/* LiteOS-A has a simplified uid model; daemon runs as root. Drop = no-op. */
int hdc_osal_drop_root(uid_t uid, gid_t gid)
{
    (void)uid;
    (void)gid;
    return 0;
}

int hdc_osal_restore_root(void)
{
    return 0;
}

int hdc_osal_is_root(void)
{
    return (geteuid() == 0) ? 1 : 0;
}
