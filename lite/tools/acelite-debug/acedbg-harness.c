/*
 * Copyright (c) 2026 ohos-lite-js-ide contributors
 * SPDX-License-Identifier: Apache-2.0
 *
 * Test harness for the ACE lite debugger gate (js_debugger_gate.h) + jerryx_debugger_tcp_create_bind.
 * Mirrors Debugger::StartDebugger() under ACE_LITE_DEBUGGER_GATE without the rest of ACE, so the gate and
 * the loopback bind can be exercised in the qemu jsdebug env (static la64, runs under qemu-loongarch64).
 *   usage: acedbg-harness [--bundle NAME] [jerry-style flags ignored] file.js
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "jerryscript.h"
#include "jerryscript-ext/debugger.h"
#include "jerryscript-ext/handler.h"
#include "jerryscript-port-default.h"
#include "js_debugger_gate.h"

static char *ReadFile(const char *path, size_t *len)
{
    FILE *f = fopen(path, "rb");
    if (f == NULL) {
        return NULL;
    }
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *b = malloc((size_t)n + 1);
    if (b == NULL || fread(b, 1, (size_t)n, f) != (size_t)n) {
        fclose(f);
        free(b);
        return NULL;
    }
    fclose(f);
    *len = (size_t)n;
    return b;
}

static void *AllocContext(size_t size, void *cb)
{
    (void)cb;
    return malloc(size);
}

int main(int argc, char **argv)
{
    const char *bundle = getenv("ACE_BUNDLE");
    const char *file = NULL;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--bundle") == 0 && i + 1 < argc) {
            bundle = argv[++i];
        } else if (strcmp(argv[i], "--debug-port") == 0 || strcmp(argv[i], "--log-level") == 0) {
            i++; /* jerry-main flags passed by run-qemu-hdcd.sh: ignored, the gate decides */
        } else if (argv[i][0] != '-') {
            file = argv[i];
        }
    }
    if (file == NULL) {
        fprintf(stderr, "usage: %s [--bundle NAME] file.js\n", argv[0]);
        return 2;
    }
    if (bundle == NULL) {
        bundle = "com.example.sample";
    }
    /* libs are built with JERRY_EXTERNAL_CONTEXT=ON (as in OH / Debugger::SetupJSContext) */
    jerry_context_t *ctx = jerry_create_context(512 * 1024, AllocContext, NULL);
    if (ctx == NULL) {
        return 3;
    }
    jerry_port_default_set_current_context(ctx);
    jerry_init(JERRY_INIT_EMPTY);
    jerryx_handler_register_global((const jerry_char_t *)"print", jerryx_handler_print);

    AceDbgGate gate;
    AceDbgGateResolve(bundle, 5001, &gate);
    printf("[gate] bundle=%s wait=%d bind=%s port=%u reason=%s\n", bundle, gate.wait, gate.bind,
           (unsigned)gate.port, gate.reason);
    fflush(stdout);
    if (gate.wait) {
        jerry_port_default_set_log_level(JERRY_LOG_LEVEL_DEBUG);
        bool protocol = jerryx_debugger_tcp_create_bind(gate.bind, gate.port);
        bool connected = jerryx_debugger_ws_create();
        jerryx_debugger_after_connect(protocol && connected);
    }

    size_t len = 0;
    char *src = ReadFile(file, &len);
    if (src == NULL) {
        fprintf(stderr, "cannot read %s\n", file);
        return 2;
    }
    jerry_value_t code = jerry_parse((const jerry_char_t *)file, strlen(file), (const jerry_char_t *)src, len,
                                     JERRY_PARSE_NO_OPTS);
    int rc = 0;
    if (jerry_value_is_error(code)) {
        rc = 1;
    } else {
        jerry_value_t r = jerry_run(code);
        rc = jerry_value_is_error(r) ? 1 : 0;
        jerry_release_value(r);
    }
    jerry_release_value(code);
    free(src);
    jerry_cleanup();
    free(ctx);
    printf("[gate] exit rc=%d\n", rc);
    return rc;
}
