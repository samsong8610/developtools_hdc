/*
 * Copyright (C) 2026 Sam Song
 * Licensed under the Apache License, Version 2.0
 *
 * LiteOS-A OSAL (stub/POSIX fallback). Selected by -DHDC_OSAL_TARGET=liteos_a.
 * Compile/link-verified only; NOT run on LiteOS-A hardware.
 */
/*
 * LiteOS-A has no OH init syspara in lite builds we target; the Linux
 * file-KV implementation is plain POSIX stdio (+ hdc_osal_mkdir_p), so it is
 * reused verbatim. Paths/overrides identical (HDC_OSAL_*_PARA, HDCD_PARAM_*).
 * TODO(liteos_a): switch to SysParam (GetParameter from startup_lite) if the
 * target image provides it.
 */
#include "../linux/param.c"
