#!/bin/bash
# One-command relink of b/acelite-la64/libace_lite.so with board DT_NEEDED sonames.
# Requires a prior full build (objects in b/acelite-la64/obj/, jerry .so present).
#
# Usage:
#   BOARD_NEEDED="libui.so libhilog_shared.so libace_native_engine.so ..." \
#     lite/tools/board/relink-board-needed.sh
#   # or:
#   lite/tools/board/relink-board-needed.sh libui.so libhilog_shared.so
#
# Prints new sha256 of libace_lite.so. Does NOT touch jerry libs (they keep their NEEDED).
set -euo pipefail
H=$(cd "$(dirname "$0")" && pwd)
PORT=${PORT:-/workspace/hdcd-port}
O=${OUT:-$PORT/b/acelite-la64}
CR=${OHOS_CLANG_ROOT:-/workspace/ohos-clang/clang_linux-x86_64-feef13-20251209}; C=$CR/bin
SR=${OHOS_SYSROOT:-/workspace/hdcd-feas/sysroot-ohos-la64}
T="--target=loongarch64-linux-ohos --sysroot=$SR"
[ -d "$O/obj" ] && ls "$O/obj"/*.o >/dev/null 2>&1 || { echo "no objects in $O/obj — run lite/tools/acelite-debug/build.sh first" >&2; exit 1; }
[ -f "$O/libjerry-core.so" ] || { echo "missing $O/libjerry-core.so" >&2; exit 1; }
if [ $# -gt 0 ]; then BOARD_NEEDED="$*"; fi
BOARD_NEEDED=${BOARD_NEEDED:?pass BOARD_NEEDED="liba.so libb.so" or args}
mkdir -p "$O/stub"
echo 'void __ohjs_stub(void){}' > "$O/stub/s.c"
for so in libc.so $BOARD_NEEDED; do
  $C/clang $T -shared -nostdlib -fPIC -o "$O/stub/$so" "$O/stub/s.c" -Wl,-soname,$so
done
EXTRA=$(for so in $BOARD_NEEDED; do printf -- '-l:%s ' "$so"; done)
LS="-nostdlib -L$O/stub -L$CR/lib/loongarch64-linux-ohos -lc"
$C/clang++ $T -shared -o "$O/libace_lite.so" -Wl,-soname,libace_lite.so \
  "$O"/obj/*.o -L"$O" -ljerry-core -ljerry-ext -ljerry-port-default $EXTRA $LS -lc++
$C/llvm-nm -D --undefined-only "$O/libace_lite.so" | awk '{print $2}' > "$O/ace_undefined.txt"
$C/llvm-readelf -d "$O/libace_lite.so" | grep NEEDED
echo "undefined=$(wc -l < "$O/ace_undefined.txt")"
sha256sum "$O/libace_lite.so"
# refresh sha file if present
if [ -f "$O/SHA256SUMS" ]; then
  (cd "$O" && sha256sum libace_lite.so libjerry-core.so libjerry-ext.so libjerry-port-default.so > SHA256SUMS)
fi
