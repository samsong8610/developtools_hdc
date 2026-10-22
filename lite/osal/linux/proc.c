/*
 * Copyright (C) 2026 Sam Song
 * Licensed under the Apache License, Version 2.0
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
    ssize_t n;
    if (buf == NULL || size == 0) {
        return -1;
    }
    n = readlink("/proc/self/exe", buf, size - 1);
    if (n < 0) {
        return -1;
    }
    buf[n] = '\0';
    return 0;
}

int hdc_osal_mkdir_p(const char *path)
{
    char tmp[512];
    size_t len;
    size_t i;
    if (path == NULL || path[0] == '\0') {
        return -1;
    }
    snprintf(tmp, sizeof(tmp), "%s", path);
    len = strlen(tmp);
    if (len == 0) {
        return -1;
    }
    if (tmp[len - 1] == '/') {
        tmp[len - 1] = '\0';
    }
    for (i = 1; tmp[i] != '\0'; ++i) {
        if (tmp[i] == '/') {
            tmp[i] = '\0';
            if (mkdir(tmp, 0755) != 0 && errno != EEXIST) {
                return -1;
            }
            tmp[i] = '/';
        }
    }
    if (mkdir(tmp, 0755) != 0 && errno != EEXIST) {
        return -1;
    }
    return 0;
}

int hdc_osal_read_file(const char *path, char *buf, unsigned size)
{
    int fd;
    ssize_t n;
    if (path == NULL || buf == NULL || size == 0) {
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
    char tmp[768];
    int fd;
    ssize_t w;
    if (path == NULL || data == NULL) {
        return -1;
    }
    snprintf(tmp, sizeof(tmp), "%s.tmp", path);
    fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) {
        return -1;
    }
    w = write(fd, data, len);
    if (w < 0 || (unsigned)w != len) {
        close(fd);
        unlink(tmp);
        return -1;
    }
    if (fsync(fd) != 0) {
        close(fd);
        unlink(tmp);
        return -1;
    }
    close(fd);
    if (rename(tmp, path) != 0) {
        unlink(tmp);
        return -1;
    }
    return 0;
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
