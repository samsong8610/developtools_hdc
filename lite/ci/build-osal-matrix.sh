#!/bin/bash
# Compile gate: HDC_OSAL_TARGET=linux (primary) + liteos_a (stub must keep building).
#
# Usage:
#   lite/ci/build-osal-matrix.sh              # auto: la64 if toolchain+deps, else host-cc
#   lite/ci/build-osal-matrix.sh host-cc      # host gcc: compile/link OSAL .a only (no OH sysroot)
#   lite/ci/build-osal-matrix.sh la64         # OHOS clang static LA64: cmake hdc_osal (+ optional hdcd)
#   lite/ci/build-osal-matrix.sh la64-osal    # LA64 hdc_osal lib only (faster)
#
# Exit 0 = both targets OK. Env: PORT, OHOS_CLANG_ROOT, OHOS_SYSROOT, HDCD_DEPS_ROOT, HDCD_PREFIX
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)   # developtools_hdc
LITE=$ROOT/lite
PORT=${PORT:-$(cd "$ROOT/.." && pwd)}
MODE=${1:-auto}
R=0
pass(){ echo "[PASS] $*"; }
fail(){ echo "[FAIL] $*"; R=1; }

have_la64() {
  local c="${OHOS_CLANG_ROOT:-/workspace/ohos-clang/clang_linux-x86_64-feef13-20251209}/bin/clang"
  local s="${OHOS_SYSROOT:-/workspace/hdcd-feas/sysroot-ohos-la64}"
  [ -x "$c" ] && [ -d "$s" ]
}

build_host_cc() {
  local target=$1
  local out=/tmp/hdc-osal-host-$target
  rm -rf "$out"; mkdir -p "$out"
  echo "==== host-cc OSAL target=$target → $out ===="
  local src="$LITE/osal/$target"
  local inc="-I$LITE/osal/include -I$LITE/osal/include/shim -DHDC_LITE_OSAL"
  [ "$target" = liteos_a ] && inc="$inc -DHDC_OSAL_LITEOS_A -D__LITEOS_A__"
  local objs=()
  for f in param service usb pty proc priv; do
    # liteos_a/param.c includes linux/param.c — compile as one TU
    gcc -c -O1 -Wall -Wextra -Wno-unused-parameter $inc \
      "$src/$f.c" -o "$out/$f.o"
    objs+=("$out/$f.o")
  done
  ar rcs "$out/libhdc_osal.a" "${objs[@]}"
  nm "$out/libhdc_osal.a" | grep -q hdc_osal_param_init || {
    # param_init may be named differently — check any hdc_osal_
    nm "$out/libhdc_osal.a" | grep -q 'hdc_osal_' || { fail "$target: no hdc_osal_ symbols"; return; }
  }
  local n
  n=$(nm "$out/libhdc_osal.a" | grep -c ' T hdc_osal_' || true)
  echo "  symbols hdc_osal_*: $n  archive=$(ls -la "$out/libhdc_osal.a")"
  [ "$n" -ge 5 ] && pass "host-cc $target ($n symbols)" || fail "host-cc $target too few symbols ($n)"
}

build_la64() {
  local target=$1
  local osal_only=${2:-0}
  local build="${HDCD_BUILD_DIR_BASE:-$PORT/b}/ci-osal-$target"
  echo "==== la64 OSAL target=$target build=$build osal_only=$osal_only ===="
  local gen=Ninja
  if ! command -v ninja >/dev/null 2>&1; then
    gen="Unix Makefiles"
    echo "[INFO] ninja not found — using $gen"
  fi
  cmake -S "$LITE" -B "$build" -G "$gen" \
    -DCMAKE_TOOLCHAIN_FILE="$LITE/toolchain/ohos-loongarch64.cmake" \
    -DHDC_OSAL_TARGET="$target" \
    -DHDCD_DEPS_ROOT="${HDCD_DEPS_ROOT:-$PORT/deps}" \
    -DHDCD_PREFIX="${HDCD_PREFIX:-$PORT/b/prefix}" \
    >/tmp/ci-osal-$target-cmake.log 2>&1 || {
    tail -30 /tmp/ci-osal-$target-cmake.log
    fail "cmake $target"
    return
  }
  if [ "$osal_only" = 1 ]; then
    cmake --build "$build" --target hdc_osal -j"$(nproc)" \
      >/tmp/ci-osal-$target-build.log 2>&1 || {
      tail -40 /tmp/ci-osal-$target-build.log
      fail "build hdc_osal $target"
      return
    }
    find "$build" -name 'libhdc_osal.a' | head -1 | grep -q . \
      && pass "la64 hdc_osal $target" || fail "la64 hdc_osal $target missing .a"
  else
    cmake --build "$build" -j"$(nproc)" >/tmp/ci-osal-$target-build.log 2>&1 || {
      tail -40 /tmp/ci-osal-$target-build.log
      fail "build hdcd $target"
      return
    }
    [ -x "$build/hdcd" ] && pass "la64 hdcd $target" || fail "la64 hdcd $target missing"
  fi
}

echo "==== build-osal-matrix mode=$MODE root=$ROOT ===="
case "$MODE" in
  auto)
    if have_la64 && [ -f "${HDCD_PREFIX:-$PORT/b/prefix}/lib/libuv.a" ]; then
      MODE=la64-osal
    else
      MODE=host-cc
      echo "[INFO] no LA64 toolchain/deps — falling back to host-cc"
    fi
    ;;
esac

case "$MODE" in
  host-cc)
    build_host_cc linux
    build_host_cc liteos_a
    ;;
  la64-osal)
    build_la64 linux 1
    build_la64 liteos_a 1
    ;;
  la64)
    build_la64 linux 0
    build_la64 liteos_a 0
    ;;
  *)
    echo "usage: $0 [auto|host-cc|la64|la64-osal]" >&2
    exit 2
    ;;
esac

echo "RESULT=$R mode=$MODE"
exit $R
