# Hand-backport checklist: `ohjs/6.1-lite` → OpenHarmony-v5.0.3-Release

**Audience:** Sam (manual port)  
**Source tip:** `ohjs/6.1-lite` (see `git rev-parse HEAD`)  
**Upstream base (6.1):** `51794b3` · **v5 target:** `3575a53` (OpenHarmony-v5.0.3-Release)  
**Detail / risk:** [`../PORT.md`](../PORT.md) §1–§18 · themes: [`CHANGELOG-ohjs-6.1-lite.md`](CHANGELOG-ohjs-6.1-lite.md)

Rule: copy `lite/**` as a tree; touch v5 `src/` **only** under `#ifdef HDC_LITE_OSAL`.

---

## Suggested order (do not skip)

| Step | What | PORT | Risk |
|---|---|---|---|
| **A** | Copy entire `lite/` tree into v5 `developtools_hdc/lite/` | — | none |
| **B** | Trim `lite/CMakeLists.txt` source lists (drop 6.1-only files below) | §1 | medium |
| **C** | Apply upstream hunks: `usb_ffs.h` → `system_depend.cpp` → `main.cpp` → `daemon_unity.cpp` (tmode + hilog) | §1–§3, §9 | low→medium |
| **D** | Build `-DHDC_OSAL_TARGET=linux` static (or native smoke); TCP tconn | — | — |
| **E** | Optional: board scripts / qemu-ide / docs (no daemon dependency) | §8+ | none |
| **F** | Do **not** need `liteos_a` for first v5 bring-up (stub only) | §7 | — |

---

## Concrete file list

### A. New tree — copy as-is (`lite/`)

```
lite/CMakeLists.txt
lite/build.sh
lite/build-native.sh
lite/deps.lock
lite/PORT.md
lite/etc/hdcd.para
lite/toolchain/ohos-loongarch64.cmake
lite/osal/README.md
lite/osal/include/hdc_osal/{osal,param,priv,proc,pty,service,usb}.h
lite/osal/include/shim/{parameter,parameters,init_reboot}.h
lite/osal/linux/{param,priv,proc,pty,service,usb}.c
lite/osal/liteos_a/{README.md,param,priv,proc,pty,service,usb}.c
lite/docs/{CHANGELOG-ohjs-6.1-lite,BACKPORT-v5.0.3,IDE-CONTRACT,JS-DEBUG}.md
lite/tools/board/**          # optional for first daemon bring-up
lite/tools/acelite-debug/**  # optional (ACE/jerry lab)
lite/test/qemu-ide/**        # optional
lite/test/usb-vm/**          # optional
```

### B. CMake drops on v5 (6.1-only objects)

Remove from `DAEMON_SRC` / `COMMON_SRC` (and matching `-D`) if absent on v5:

| Drop from CMake | Also drop define |
|---|---|
| `common/memory_pool.cpp` | `MEMORY_POOL_ENABLE` |
| `common/hdc_ssl.cpp`, `daemon/daemon_ssl.cpp` | `HDC_SUPPORT_ENCRYPT_TCP` |
| `common/heartbeat.cpp` | — |
| `common/hdc_statistic_reporter.cpp` | — |
| `common/server_cmd_log.cpp` | — |
| `common/connect_validation.cpp` | — |
| `common/uv_status.cpp` | — |

Re-check shim headers against v5 include usage of `parameters.h`.

### C. Upstream `src/` hunks (apply by hand)

| File | PORT | What to port |
|---|---|---|
| `src/daemon/usb_ffs.h` | §1 | `USB_FFS_BASE` → `hdc_osal_usb_get_ffs_base()` under `HDC_LITE_OSAL` |
| `src/daemon/system_depend.cpp` | §1 | `HARMONY_PROJECT \|\| HDC_LITE_OSAL` on Set/GetParameter; `CallDoReboot` → `DoReboot()` in lite |
| `src/daemon/main.cpp` | §3 | `#include` OSAL; `hdc_osal_param_init()` before developermode; `RestartDaemon` → `hdc_osal_restart_self` |
| `src/daemon/daemon_unity.cpp` | §3, §9 | tmode success → `PostStopInstanceMessage(true)`; `GetHiLog` → `hdc_osal_hilog_cmd()` |

**Diff size at 6.1 tip (illustrative):** ~78 files / +6782 under `lite/` + small `src/daemon` edits. Re-generate on tip:

```sh
git diff --stat 51794b3..HEAD -- lite/ src/daemon/
git diff 51794b3..HEAD -- src/daemon/usb_ffs.h src/daemon/system_depend.cpp \
  src/daemon/main.cpp src/daemon/daemon_unity.cpp
```

Cherry-pick is **not** recommended across 6.1↔5.0.3; use the hunk list above.

---

## Smoke after port

```sh
# Device TCP (adjust paths)
hdc -v                                    # Ver: 3.2.0c on 6.1 host; v5 host may differ — match device protocol
export OHOS_HDC_SERVER_PORT=8711
hdc -s 127.0.0.1:8711 tconn <ip>:8710
hdc -s 127.0.0.1:8711 -t <ip>:8710 shell 'echo ok; echo __RC=$?'
```

IDE ports/paths: [`IDE-CONTRACT.md`](IDE-CONTRACT.md) (written for 6.1 Ver 3.2.0c — re-validate hash on v5).
