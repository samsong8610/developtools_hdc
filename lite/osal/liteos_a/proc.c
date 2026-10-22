/*
 * Copyright (C) 2026 Sam Song
 * Licensed under the Apache License, Version 2.0
 *
 * LiteOS-A OSAL (stub/POSIX fallback). Selected by -DHDC_OSAL_TARGET=liteos_a.
 * Compile/link-verified only; NOT run on LiteOS-A hardware.
 */
#include "hdc_osal/proc.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

int hdc_osal_exepath(char *buf, unsigned size)
{
    const char *env = getenv("HDC_OSAL_EXEPATH");
    ssize_t n;
    if (buf == NULL || size == 0) {
        errno = EINVAL;
        return -1;
    }
    if (env != NULL && env[0] != '\0') {
        snprintf(buf, size, "%s", env);
        return 0;
    }
    /* LiteOS-A procfs may lack /proc/self/exe; try it, else fixed default. */
    n = readlink("/proc/self/exe", buf, size - 1);
    if (n > 0) {
        buf[n] = '\0';
        return 0;
    }
    snprintf(buf, size, "%s", "/bin/hdcd");
    return 0;
}

int hdc_osal_mkdir_p(const char *path)
{
    char tmp[512];
    size_t i;
    size_t len;
    if (path == NULL || path[0] == '\0') {
        errno = EINVAL;
        return -1;
    }
    snprintf(tmp, sizeof(tmp), "%s", path);
    len = strlen(tmp);
    for (i = 1; i <= len; ++i) {
        if (tmp[i] == '/' || tmp[i] == '\0') {
            char c = tmp[i];
            tmp[i] = '\0';
            if (mkdir(tmp, 0755) != 0 && errno != EEXIST) {
                return -1;
            }
            tmp[i] = c;
        }
    }
    return 0;
}

int hdc_osal_read_file(const char *path, char *buf, unsigned size)
{
    int fd;
    ssize_t n;
    if (path == NULL || buf == NULL || size == 0) {
        errno = EINVAL;
        return -1;
    }
    fd = open(path, O_RDONLY);
    if (fd < 0) {
        return -1;
    }
    n = read(fd, buf, size - 1);
    close(fd);
    if (n < 0) {
        return -1;
    }
    buf[n] = '\0';
    return (int)n;
}

int hdc_osal_write_file(const char *path, const char *data, unsigned len)
{
    int fd;
    ssize_t n;
    if (path == NULL || data == NULL) {
        errno = EINVAL;
        return -1;
    }
    fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) {
        return -1;
    }
    n = write(fd, data, len);
    close(fd);
    return (n == (ssize_t)len) ? 0 : -1;
}

const char *hdc_osal_hilog_cmd(int help)
{
    const char *env = getenv("HDC_OSAL_HILOG_CMD");
    if (env != NULL && env[0] != '\0') {
        return env;
    }
    if (help) {
        return "if command -v hilog >/dev/null 2>&1; then hilog -h; else hilogcat -h; fi";
    }
    return "if command -v hilog >/dev/null 2>&1; then exec hilog; else exec hilogcat; fi";
}
