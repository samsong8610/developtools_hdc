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

---

## G4 status (2026-10-22 22:00 Asia/Shanghai)

### A. Emulated end-to-end debug session: PASS
`lite/test/qemu-ide/verify-jsdebug.sh` (log: `test/qemu-jsdebug.log`).
- **Debuggee:** `jerry` 2.3.0 (6.1-LTS `third_party_jerryscript`) built static for loongarch64 with `JERRY_DEBUGGER=ON` (`lite/test/qemu-ide/build-jerry.sh`).
  It runs under qemu-loongarch64: `jerry --start-debug-server --debug-port 5001 sample.js`.
- **Isolation:** `run-qemu-hdcd.sh jsdebug` puts hdcd and jerry in a **network namespace that has only loopback**.
  The host reaches hdcd only through a socat bridge (`127.0.0.1:18710` → netns `127.0.0.1:8710`), and the script asserts that host `127.0.0.1:5001` is closed.
  So the debugger traffic provably goes **through hdcd fport**. jerry logs `Connected from: 127.0.0.1` inside the netns.
- **Flow:** `hdc -s 127.0.0.1:8711 tconn 127.0.0.1:18710` → `fport tcp:19001 tcp:5001` → `python2 jerry_client.py --non-interactive localhost:19001`.
  Then `b sample.js:3`, `c`, `bt`, `e a+b`, `c`. Output:
```
Stopped at sample.js:1
Breakpoint 1 at sample.js:3 (in add() at line:2, col:1)
Stopped at breakpoint:1 sample.js:3 (in add() at line:2, col:1)
Frame 0: sample.js:3 (in add() at line:2, col:1)
Frame 1: sample.js:7
(jerry-debugger) e a+b
10
out: done counter=33
```
- **Client note:** the 6.1-LTS `jerry_client.py` is **python2-only**; under python3 it fails on `ord()` and bytes/str.
  Upstream jerryscript v2.4.0's client is also py2, with the same protocol version 9. Here python 2.7.18 was built at `/workspace/py27/inst`.
  The IDE needs a py2 runtime or a py3 port of the client.

### B. Debug ACE lite + Jerry libs for loongarch64: compiled and linked, NOT validated
`lite/tools/acelite-debug/build.sh` (+ `ace_engine_lite-debugger.patch`, `jerryscript-debugger-bind.patch`).

**Patch:** `ENGINE_DEBUGGER=1` via `-DACE_LITE_FORCE_ENGINE_DEBUGGER`, plus a **runtime gate** for starting the server via `-DACE_LITE_DEBUGGER_GATE`. The gate is default off and binds 127.0.0.1 (see E). Both are opt-in macros, so default builds are unchanged. (The earlier `ACE_LITE_DEBUGGER_AUTOSTART`, which made every app wait, has been removed.)

**Result:**
- All 99 ACE core sources from `ace_lite.gni` compile with the OHOS clang `--target=loongarch64-linux-ohos`.
- `libace_lite.so` links and contains `please connect to debugger server`.
- `libjerry-core.so`, `libjerry-ext.so` and `libjerry-port-default.so` are built with debugger + external context.

**Output:** `/workspace/hdcd-port/b/acelite-la64/`.

| file | sha256 |
|---|---|
| `libace_lite.so` | `b85a5416703d72ebe1368586deebe129c95ff787e185cc8a989a587261a7919c` |
| `libjerry-core.so` | `3cb9d344b41101a6ba42ac7de00f61dd8398114d36fd99603ac89ba12103c9a2` |
| `libjerry-ext.so` | `35f522de2b6d6ee2ce150bfccb900b7a65f2517de42b97d91b7dc83fa3c44641` (adds `jerryx_debugger_tcp_create_bind`) |
| `acedbg-harness` (test only, static) | `b14e2b4717a8f019cebbf5ae9677712dc3675a8752869ec69da3af36cf7ef696` |
| `libjerry-port-default.so` | `fcb9ce04d2f4d39c32a923e5baaf880feb5666d17e9a72680f8d01c409a3e70b` |

**What is missing or unverified (do not deploy blindly):**
1. **No libc.so in the temporary sysroot** (static musl only). The libs link against a `libc.so` soname stub and the clang `libc++.so`. Real musl/libc++ ABI on the board is unverified.
2. **404 undefined symbols** (`b/acelite-la64/ace_undefined.txt`) are expected to come from board libs:
   - ui_lite (`OHOS::UIView`…), graphic_utils, ability_lite;
   - `libace_native_engine.so` (JSI) and `libace_module_manager.so`;
   - hilog, samgr, and the platform adapter (`ace_malloc`, `Terminate`, `SetEngineSnapshotMode`…).

   Our `.so` has **no DT_NEEDED for them**. Pass `BOARD_NEEDED="<exact NEEDED list from board>"` to `lite/tools/acelite-debug/build.sh`, or use `lite/tools/board/relink-board-needed.sh` after a full build (see above).
3. **Feature-flag mismatch risk:** the board's ACE/jerry build flags are unknown.
   - Examples: `ace_lite_common_defines` (netstack/battery/kv/media/camera), product `acelite_config.h` (we used `targets/linux`), and jerry `JERRY_ES2015`, `JERRY_SNAPSHOT_*`, `JERRY_CPOINTER_32_BIT`, heap size.
   - A mismatch can corrupt the external-context layout, or break **snapshot (.bc) compatibility**, which ACE lite uses for app JS.
4. **Other libs use jerry too.** Board `libace_native_engine.so` / `libace_module_manager.so` link the board's jerry, so replacing jerry libs affects them. Replace all three jerry libs together, and only if the board's jerry exports the same API.
5. The sources were shallow GitHub mirrors of the tag. The board image may carry vendor patches.

**Offline ABI compare (when Sam returns a `board-results-*.zip` with `libs/`):**

```sh
# from developtools_hdc lite/ tree (or any checkout with llvm-readelf + llvm-nm)
lite/tools/board/abi-compare.sh --board-results /path/board-results-….zip
# or after unpack:
lite/tools/board/unpack-board-results.sh board-results-….zip /tmp/br
lite/tools/board/abi-compare.sh --board-libs /tmp/br/.../libs --ours /workspace/hdcd-port/b/acelite-la64
# reports: abi-report-*/abi-report.md + abi-report.json
# Windows: abi-compare.ps1 forwards to bash/WSL; if no bash, copy libs/ to Linux and run the .sh
```

Checks per matching `.so`: ELF machine/class/type, flags, SONAME, DT_NEEDED diff, defined-export set diff (ours must be a **superset** of board), undefined counts, `.text` size delta, debugger string, jerry debugger symbols (`tcp_create_bind` etc.).
Verdict: **YES / CONDITIONAL (relink BOARD_NEEDED) / NO**.

**BOARD_NEEDED one-command relink** (after a full `acelite-debug/build.sh`, once board NEEDED is known from the report):

```sh
BOARD_NEEDED="libui.so libhilog_shared.so libace_native_engine.so …" \
  lite/tools/board/relink-board-needed.sh
# then re-run abi-compare.sh; sha256 of libace_lite.so changes, jerry libs unchanged
```


**Pack replaceable libs** (only if verdict is YES, or CONDITIONAL after a successful BOARD_NEEDED relink):

```sh
lite/tools/board/pack-debug-libs.sh --board-libs /tmp/br/.../libs
# → debug-libs-<timestamp>.zip  (libs + SHA256SUMS + BACKUP-AND-ROLLBACK.md + swap-libs.ps1)
# swap-libs.ps1 prints hdc steps by default; -Execute (-DoRemount) required for writes/remount.
```

One-pager: `lite/tools/board/README-ABI.md` (also shipped in the board package).

Smoke (no board zip needed): `lite/tools/board/smoke-abi-compare.sh` / `smoke-pack-debug-libs.sh` (identical → YES; x86 stub → NO; extra NEEDED → CONDITIONAL).

Current build shas are also in `b/acelite-la64/SHA256SUMS` (written by `build.sh`).

**Required from the board before any swap** (paste back):
```sh
for f in $(find / \( -name 'libace_lite*.so' -o -name 'libjerry*.so' -o -name 'libace_native_engine.so' -o -name 'libace_module_manager.so' \) 2>/dev/null); do
  echo "== $f"; ls -l "$f"; sha256sum "$f"
  readelf -d "$f" | grep -E 'NEEDED|SONAME'          # or llvm-readelf on host after hdc file recv
  readelf -h "$f" | grep -E 'Flags|Machine'
  strings "$f" | grep -m3 -E 'JERRY|please connect to debugger server|GCC|clang version'
done
# then on host: hdc file recv <path> ./board-libs/ ; llvm-nm -D --defined-only ./board-libs/libace_lite.so > board_exports.txt
# compare: our exports (llvm-nm -D --defined-only b/acelite-la64/libace_lite.so) must be a superset of board_exports.txt
```

### C. Replace / backup / rollback (board; only after B checks pass)
```sh
# 0) record & backup
L=$(find / -name libace_lite.so 2>/dev/null | head -1); D=$(dirname $L); echo $D
mount | grep -E " $(df $D | tail -1 | awk '{print $NF}') "         # ro?
mkdir -p /data/ohjs-bak && cp -a $D/libace_lite.so $D/libjerry-*.so /data/ohjs-bak/ && sha256sum /data/ohjs-bak/*
# 1) make writable (system partition is usually ro; may be dm-verity/signed -> remount can fail or boot can fail later)
mount -o remount,rw $(df $D | tail -1 | awk '{print $NF}')
# 2) push (host)
#    hdc file send b/acelite-la64/libace_lite.so /data/ohjs-new/libace_lite.so   (same for libjerry-*.so)
cp /data/ohjs-new/*.so $D/ && sync
# 3) restart app & verify
aa terminate -p <bundle>; aa start -p <bundle> -n <ability>
strings $D/libace_lite.so | grep -c 'please connect to debugger server'   # 1
netstat -ltn | grep ':5001'                                              # nothing: the gate is off by default
#    enable for one bundle (see E): touch /data/ohjs/debug.<bundle> ; aa start ... ; netstat -> 127.0.0.1:5001 LISTEN (app blocks)
#    host: hdc fport tcp:19001 tcp:5001 ; python2 jerry_client.py localhost:19001
# 4) rollback
mount -o remount,rw <mnt>; cp -a /data/ohjs-bak/*.so $D/ && sync; mount -o remount,ro <mnt>
aa terminate -p <bundle>; netstat -ltn | grep -c ':5001'   # 0 after restart
```
If the device does not boot or the app crashes at load (`hilogcat` shows dlopen/undefined-symbol errors), roll back.
If the system will not boot, recovery means reflashing the system image. Keep that image at hand before step 1.

### D. Risks (summary)
- **ABI / feature-flag mismatch:** libc/libc++, jerry config, external context, snapshot version (see B.1–B.4). This is the highest risk, and it can only be checked against the board's original libs.
- **Signed / verified system partition:** dm-verity or a signed image may reject a modified `/system` (remount fails, or boot fails), and a release build may refuse it.
- **Read-only system partition:** needs `remount,rw`, which may be impossible on production firmware.
- **The app blocks** at launch until a debugger client connects (accept in `jerryx_debugger_tcp_create_bind`). This happens **only** when the gate is on for that bundle (E). A stale flag file or param makes the app hang at start, so the IDE must remove it when the debug session ends.
- **Exposure:** the server binds `127.0.0.1:5001` by default, so it is reachable only on the device, i.e. through hdc fport. There is no authentication. `bind=0.0.0.0` (flag file, `ace.debugger.bind`, or `ACE_DEBUGGER_BIND`) re-exposes it on all interfaces.
- **New symbol dependency:** the debug `libace_lite.so` needs `jerryx_debugger_tcp_create_bind`, which only the patched `libjerry-ext.so` provides. Always deploy them together. It also now imports `dlsym`, `getenv`, `fopen`, `fgets`, `inet_pton`, `snprintf` and `strtol` (all libc).

### E. Runtime wait-for-debugger gate + loopback bind (`ACE_LITE_DEBUGGER_GATE`)
`frameworks/include/base/js_debugger_gate.h` (added by `ace_engine_lite-debugger.patch`) is called from
`Debugger::StartDebugger()` (after the framework loads, before app JS runs) with the current bundle name.
**Default: off.** The server is not started and the app does not wait. The gate turns on only through one of the
sources below. Later sources override earlier ones.

| # | source | enable | port / bind |
|---|---|---|---|
| 1 | param `const.ace.debugger.wait` (product default), then `ace.debugger.wait` (runtime: `param set`) | `1`/`true`/`all`/`on` = every bundle; a comma list of bundle names = those bundles; `0`/`false`/`off` = off | `ace.debugger.port`, `ace.debugger.bind` |
| 2 | flag file `/data/ohjs/debug.<bundle>` (the dir can be overridden with env `ACE_DEBUGGER_FLAG_DIR`) | the file exists | optional lines `port=N`, `bind=A.B.C.D` |
| 3 | env `ACE_DEBUGGER_WAIT` | `1` forces on, `0` forces off (or a bundle list) | `ACE_DEBUGGER_PORT`, `ACE_DEBUGGER_BIND` |

- **Defaults.** The port defaults to 5001 and the bind address to **127.0.0.1**. An invalid port or address is
  ignored and the default is kept.
- **Param reads.** Params are read through `dlsym(RTLD_DEFAULT, "GetParameter")`. If no loaded library exports
  it, the param source is skipped, so the library gets no new DT_NEEDED.
- **Logs.** The decision is logged to hilog as `js debugger on|off for <bundle> (<reason>)`. When the gate is on,
  stdout also shows `[ace] js debugger waiting on 127.0.0.1:5001`.
- **Recommended IDE flow (per launch):**
  ```sh
  hdc shell "mkdir -p /data/ohjs && touch /data/ohjs/debug.<bundle>"
  aa start -p <bundle> -n <ability>   # app blocks in accept on 127.0.0.1:5001
  hdc fport tcp:19001 tcp:5001        # then attach @ohjs/jerry-debug-client to 127.0.0.1:19001
  hdc shell rm /data/ohjs/debug.<bundle>   # right after attach, so the next normal launch does not wait
  ```

**Emulated verification:** `lite/test/qemu-ide/verify-acedbg-gate.sh`, log in `test/qemu-acedbg-gate.log`.
- It runs `b/acelite-la64/acedbg-harness`, a static la64 binary that uses the same `js_debugger_gate.h` and the
  same patched jerry-ext as `libace_lite.so`. It runs in the jsdebug netns through
  `run-qemu-hdcd.sh jsdebug` (new env `JERRY_BIN`/`JERRY_ARGS`/`JERRY_ENV`).
- All of these checks PASS:
  - Default: no listener, and the app runs to completion.
  - `ACE_DEBUGGER_WAIT=1`: the app waits, and the listener is **`127.0.0.1:5001` only**.
  - The full `@ohjs/jerry-debug-client` e2e runs through `hdc fport` against the loopback-bound server: breakpoint, backtrace, eval `a+b=10`, step, and run to end.
  - The flag file gates its own bundle only.
  - A `bind=0.0.0.0` override is honoured, both from the flag file and from env.

**Not verified:**
- The param source. The static harness has no `GetParameter`, so the param path is only compile-checked.
- `libace_lite.so` itself on a board: same ABI caveats as B.
