#!/bin/bash
# Build a NATIVE (host x86_64) static hdcd from the same lite/ CMake + OSAL,
# for USB FunctionFS emulation (QEMU + dummy_hcd). Not a shipping artifact.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="$(cd "$ROOT/.." && pwd)"
DEPS="${HDCD_DEPS_ROOT:-$PORT/deps}"
N="${HDCD_NATIVE_DIR:-$PORT/b/native}"
PREFIX="$N/prefix"; CC="${CC:-gcc}"; AR="${AR:-ar}"
mkdir -p "$PREFIX/lib" "$PREFIX/include" "$PORT/gen"
if [ ! -f "$PREFIX/lib/libuv.a" ]; then
  U="$DEPS/third_party_libuv"
  cmake -S "$U" -B "$N/uv" -G Ninja -DLIBUV_BUILD_SHARED=OFF -DLIBUV_BUILD_TESTS=OFF -DCMAKE_BUILD_TYPE=Release
  ninja -C "$N/uv" uv_a; cp -f "$N/uv/libuv.a" "$PREFIX/lib/"
  for f in trace_unix log_unix; do $CC -O2 -I"$U/include" -I"$U/src" -c "$U/src/unix/$f.c" -o "$N/uvx_$f.o"; done
  cp -a "$U/include/." "$PREFIX/include/"
fi
if [ ! -f "$PREFIX/lib/libsec.a" ]; then
  SB="$DEPS/third_party_bounds_checking_function"; mkdir -p "$N/sec"
  for f in "$SB"/src/*.c; do $CC -O2 -I"$SB/include" -c "$f" -o "$N/sec/$(basename "$f" .c).o"; done
  $AR rcs "$PREFIX/lib/libsec.a" "$N/sec"/*.o; cp -f "$SB"/include/*.h "$PREFIX/include/"
fi
if [ ! -f "$PREFIX/lib/liblz4.a" ]; then
  rm -rf "$N/lz4"; cp -a "$DEPS/third_party_lz4" "$N/lz4"
  make -s -C "$N/lz4/lib" liblz4.a CC="$CC"; cp -f "$N/lz4/lib/liblz4.a" "$PREFIX/lib/"; cp -f "$N/lz4/lib/lz4.h" "$PREFIX/include/"
fi
if [ ! -f "$PREFIX/lib/libssl.a" ]; then
  rm -rf "$N/ossl"; cp -a "$DEPS/third_party_openssl" "$N/ossl"; cd "$N/ossl"
  ./Configure linux-x86_64 no-shared no-tests no-asm --prefix="$PREFIX" --libdir=lib >/dev/null
  make -s -j"$(nproc)" build_libs && make -s install_dev
fi
[ -f "$PORT/gen/hdc_hash_gen.h" ] || printf '%s\n' '#pragma once' '#define HDC_MSG_HASH "7fdbc1aa8c5fefaa"' > "$PORT/gen/hdc_hash_gen.h"
cmake -S "$ROOT/lite" -B "$N/build" -G Ninja -DHDCD_DEPS_ROOT="$DEPS" -DHDCD_PREFIX="$PREFIX" \
  -DHDCD_UVX_DIR="$N" -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CXX_FLAGS="-include cstdlib"  # libstdc++ needs it (musl/libc++ gets it transitively)
cmake --build "$N/build" -j"$(nproc)"
mkdir -p "$N/out"; cp -f "$N/build/hdcd" "$N/out/hdcd"; strip -o "$N/out/hdcd.stripped" "$N/out/hdcd"
ls -la "$N/out"
