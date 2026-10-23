# Lite CI helpers (no board)

| Script | Role |
|---|---|
| `build-osal-matrix.sh` | Compile gate: `HDC_OSAL_TARGET=linux` + `liteos_a` stub |

```sh
# Always (laptop / GHA):
./lite/ci/build-osal-matrix.sh host-cc

# With OHOS clang + deps (this lab):
./lite/ci/build-osal-matrix.sh la64-osal   # libs only
./lite/ci/build-osal-matrix.sh la64        # full static hdcd both backends
```

GitHub Actions: `.github/workflows/lite-osal.yml` runs **host-cc** on push/PR touching OSAL.

## Optional soak (no board)

```bash
# After qemu-ide G2 is up:
N=20 lite/test/qemu-ide/soak-ide-contract.sh
# Env: SOAK_N / N, SOAK_SKIP_NESTED=1, SKIP_START=1
lite/tools/board/check-ide-contract-drift.sh   # anti-drift vs IDE IDE-CONTRACT.md
```

## GitHub Actions qemu-ide

Workflow: `.github/workflows/lite-qemu-ide.yml`  
Entry: `lite/ci/run-qemu-ide-ci.sh` — runs `smoke-qemu-edges` + `soak-ide-contract` (N≥20).

- **Skip** (exit 0) if `qemu-loongarch64`, `HDCD_BIN`, or host `HDC` unavailable.
- **Must PASS** when those are present (workflow fetches `ohjs-board-2026-10-29` assets when possible).
- Local: `HDCD_BIN=… HDC=… bash lite/ci/run-qemu-ide-ci.sh`

## ide-error-codes schema

```bash
bash lite/ci/validate-ide-error-codes.sh
```

Fails CI if `version` / required channels / failure fields drift from `ide-error-codes.schema.json`.
