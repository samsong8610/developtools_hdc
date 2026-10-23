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
