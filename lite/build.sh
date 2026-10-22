#!/bin/bash
# Build static loongarch64 hdcd with Lite OSAL.
# Sysroot TEMPORARY: /workspace/hdcd-feas/sysroot-ohos-la64
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="$(cd "$ROOT/.." && pwd)"
DEPS="${HDCD_DEPS_ROOT:-$PORT/deps}"
PREFIX="${HDCD_PREFIX:-$PORT/b/prefix}"
CLANG_ROOT="${OHOS_CLANG_ROOT:-/workspace/ohos-clang/clang_linux-x86_64-feef13-20251209}"
SYSROOT="${OHOS_SYSROOT:-/workspace/hdcd-feas/sysroot-ohos-la64}"
C="$CLANG_ROOT/bin"
T="--target=loongarch64-linux-ohos --sysroot=$SYSROOT"
CC="$C/clang $T"; AR="$C/llvm-ar"
BUILD="${HDCD_BUILD_DIR:-$PORT/b/lite}"
mkdir -p "$PREFIX/lib" "$PREFIX/include" "$BUILD" "$PORT/b" "$PORT/gen"

echo "[hdcd-lite] deps=$DEPS prefix=$PREFIX sysroot=$SYSROOT (temporary)"

need_uv() { [ ! -f "$PREFIX/lib/libuv.a" ]; }
need_sec() { [ ! -f "$PREFIX/lib/libsec.a" ]; }
need_lz4() { [ ! -f "$PREFIX/lib/liblz4.a" ]; }
need_ssl() { [ ! -f "$PREFIX/lib/libcrypto.a" ] || [ ! -f "$PREFIX/lib/libssl.a" ]; }

if need_uv; then
  U="$DEPS/third_party_libuv"
  cmake -S "$U" -B "$PORT/b/uv" -G Ninja \
    -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=loongarch64 \
    -DCMAKE_C_COMPILER="$C/clang" -DCMAKE_C_COMPILER_TARGET=loongarch64-linux-ohos \
    -DCMAKE_SYSROOT="$SYSROOT" -DCMAKE_AR="$AR" \
    -DLIBUV_BUILD_SHARED=OFF -DLIBUV_BUILD_TESTS=OFF -DCMAKE_BUILD_TYPE=Release
  ninja -C "$PORT/b/uv" uv_a
  cp -f "$PORT/b/uv/libuv.a" "$PREFIX/lib/"
  $CC -O2 -I"$U/include" -I"$U/src" -c "$U/src/unix/trace_unix.c" -o "$PORT/b/uvx_trace_unix.o"
  $CC -O2 -I"$U/include" -I"$U/src" -c "$U/src/unix/log_unix.c" -o "$PORT/b/uvx_log_unix.o"
  cp -a "$U/include/." "$PREFIX/include/"
fi
if need_sec; then
  SB="$DEPS/third_party_bounds_checking_function"
  mkdir -p "$PORT/b/sec"
  for f in "$SB"/src/*.c; do $CC -O2 -I"$SB/include" -c "$f" -o "$PORT/b/sec/$(basename "$f" .c).o"; done
  $AR rcs "$PREFIX/lib/libsec.a" "$PORT/b/sec"/*.o
  cp -f "$SB"/include/*.h "$PREFIX/include/"
fi
if need_lz4; then
  L="$DEPS/third_party_lz4"
  make -s -C "$L/lib" clean >/dev/null 2>&1 || true
  make -s -C "$L/lib" liblz4.a CC="$CC" AR="$AR"
  cp -f "$L/lib/liblz4.a" "$PREFIX/lib/"; cp -f "$L/lib/lz4.h" "$PREFIX/include/"
fi
if need_ssl; then
  O="$PORT/b/ossl"; rm -rf "$O"; cp -a "$DEPS/third_party_openssl" "$O"; cd "$O"
  CC="$CC" AR="$AR" RANLIB="$C/llvm-ranlib" \
    ./Configure linux64-loongarch64 no-shared no-tests no-asm --prefix="$PREFIX" --libdir=lib
  make -s -j"$(nproc)" build_libs && make -s install_dev
fi

if [ ! -f "$PORT/gen/hdc_hash_gen.h" ]; then
  printf '%s\n' '#pragma once' '#define HDC_MSG_HASH "7fdbc1aa8c5fefaa"' > "$PORT/gen/hdc_hash_gen.h"
fi
# Ensure uvx objs
if [ ! -f "$PORT/b/uvx_log_unix.o" ]; then
  U="$DEPS/third_party_libuv"
  $CC -O2 -I"$U/include" -I"$U/src" -c "$U/src/unix/trace_unix.c" -o "$PORT/b/uvx_trace_unix.o"
  $CC -O2 -I"$U/include" -I"$U/src" -c "$U/src/unix/log_unix.c" -o "$PORT/b/uvx_log_unix.o"
fi

cmake -S "$ROOT/lite" -B "$BUILD" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$ROOT/lite/toolchain/ohos-loongarch64.cmake" \
  -DOHOS_CLANG_ROOT="$CLANG_ROOT" -DOHOS_SYSROOT="$SYSROOT" \
  -DHDCD_DEPS_ROOT="$DEPS" -DHDCD_PREFIX="$PREFIX" -DCMAKE_BUILD_TYPE=Release
cmake --build "$BUILD" -j"$(nproc)"
mkdir -p "$PORT/b/out"
cp -f "$BUILD/hdcd" "$PORT/b/out/hdcd"
"$C/llvm-strip" -o "$PORT/b/out/hdcd.stripped" "$PORT/b/out/hdcd"
ls -la "$PORT/b/out/hdcd" "$PORT/b/out/hdcd.stripped"
"$C/llvm-objdump" -f "$PORT/b/out/hdcd.stripped" | head -5
