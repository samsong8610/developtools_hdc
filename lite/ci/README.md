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
