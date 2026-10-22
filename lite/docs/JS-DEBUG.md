# JS debugger on the small system (ace_engine_lite + JerryScript), OpenHarmony v6.1-LTS

Sources: `openharmony/arkui_ace_engine_lite` and `openharmony/third_party_jerryscript` at tag `OpenHarmony-v6.1-LTS` (GitHub mirrors).
Researched 2026-10-22 (Asia/Shanghai).

## Bottom line

**On a stock device build, the JS debugger is compiled out and never started.**
Enabling it needs a **rebuild of ace_engine_lite** (compile-time macro) **plus a code change** that turns on `startDebuggerServer`.
Upstream has no runtime switch, parameter, or config file for it.

## Evidence

| Layer | Fact | Source |
|---|---|---|
| ACE macro | `ENGINE_DEBUGGER` = 1 only if `TARGET_SIMULATOR == 1`, else **0 on real device** | `arkui_ace_engine_lite/frameworks/include/base/js_config.h:62-66` |
| Simulator only | `TARGET_SIMULATOR=1` is defined only by the simulator target | `frameworks/targets/simulator/BUILD.gn:57` |
| Stub when 0 | `StartDebugger()`, `ConfigEngineDebugger()`, `SetupJSContext()` are empty | `frameworks/src/core/base/js_debugger_config.cpp:123-148` |
| Runtime gate | even with the macro on, `startDebuggerServer` defaults to **false** | `frameworks/include/base/js_debugger_config.h:44,51,141` |
| Who sets it | only the Qt simulator calls `ConfigEngineDebugger`, and it also sets `startDebuggerServer = false` | `frameworks/tools/qt/simulator/entry/main.cpp:43-50` |
| Start point | `JsAppEnvironment` calls `StartDebugger()` after loading the JS framework | `frameworks/src/core/context/js_app_environment.cpp:122` |
| Protocol | **TCP + WebSocket** ("currently, only support tcp::websocket"): `jerryx_debugger_tcp_create(port)` + `jerryx_debugger_ws_create()` | `js_debugger_config.cpp:55-59` |
| Port | `DEFAULT_PORT = 5001` | `frameworks/include/base/js_debugger_config.h:38,43` |
| Bind / wait | listens on `INADDR_ANY`, backlog 1, **blocks waiting for one client** before JS runs | `third_party_jerryscript/jerry-ext/debugger/debugger-tcp.c:257,275,356` |
| Engine feature | `jerryscript_jerry_debugger = 1` (default for OHOS builds) → `-DJERRY_DEBUGGER=1` | `third_party_jerryscript/engine.gni:21`, `BUILD.gn:69,489` |
| Exception | IAR (liteos_m/iccarm) forces `JERRY_DEBUGGER=0` | `jerry-core/BUILD.gn:239-252` |
| Runtime check | `StartDebugger` also requires `jerry_is_feature_enabled(JERRY_FEATURE_DEBUGGER)` | `js_debugger_config.cpp:45` |
| Client | `jerry-debugger/jerry_client.py [host:port]`, default `localhost:5001`, `--channel websocket` (default), `--protocol tcp` (default) | `third_party_jerryscript/jerry-debugger/jerry_client_main.py:123-141` |

## Enabling it (device image, not hdcd)

1. In `js_config.h`, make `ENGINE_DEBUGGER` 1 for the device target (or add `defines += ["ENGINE_DEBUGGER=1"]` behind a product/debug gn arg).
2. Before `JsAppEnvironment` init, call `Debugger::GetInstance().ConfigEngineDebugger(cfg)` with `cfg.startDebuggerServer = true; cfg.port = 5001;` (optionally `heapSize`).
   A natural place is the JS ability launch path, gated by a debug parameter (e.g. `persist.ace.debugger=1`) that we would define. Upstream has none.
3. Keep `jerryscript_jerry_debugger = 1` (the default).
4. Caveat: the app **blocks at launch until a client connects** (debugger-tcp accept). Use this only for debug launches.

## Forwarding through hdc

The JS debugger speaks plain TCP (WebSocket framing on top), so `hdc fport` works. fport was verified with a TCP echo in `test/e2e.sh`.
```bash
hdc -t <tgt> fport tcp:19001 tcp:5001     # host 19001 -> device 5001
python3 jerry_client.py --display 10 localhost:19001
hdc -t <tgt> fport rm tcp:19001 tcp:5001
```
DevEco's lite JS debugging uses the same JerryScript WebSocket protocol on 5001. Its availability for small-system devices in current DevEco is **not verified**.

## Minimal board verification

```sh
# 1) Was the debugger compiled into ACE? (the string only exists when ENGINE_DEBUGGER=1)
L=$(find / -name 'libace_lite*.so' 2>/dev/null | head -1); echo "$L"
strings "$L" | grep -c 'please connect to debugger server'    # 0 => compiled out (stock); >=1 => compiled in
# 2) Is a server listening after starting a JS app?
aa start -p <bundle> -n <ability>; sleep 2
netstat -ltn 2>/dev/null | grep ':5001' || echo NO_5001
hilogcat | grep -m1 'please connect to debugger server'       # (Ctrl-C) expected only in debug builds
```
Expected on stock 6.1-LTS: `0` and `NO_5001`.
If the image is a debug ACE build, there is a listener on `0.0.0.0:5001`. Then run the `hdc fport` and `jerry_client.py` steps above. The client prints `Connected to JerryScript` and the app proceeds.
