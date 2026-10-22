#!/bin/bash
# Build JerryScript (OH 6.1-LTS third_party_jerryscript) with debugger, static loongarch64, OHOS clang.
# Out: $PORT/b/jerry-la64/bin/jerry (jerry-main: --start-debug-server --debug-port N)
set -euo pipefail
PORT=/workspace/hdcd-port; SRC=${JERRY_SRC:-/workspace/oh61src/third_party_jerryscript}
CLANG=${OHOS_CLANG_ROOT:-/workspace/ohos-clang/clang_linux-x86_64-feef13-20251209}/bin/clang
B=$PORT/b/jerry-la64
# JerryScript 2.3 sets -Werror=<x> that newer clang trips on; strip -Werror* only.
cat > $PORT/b/jerry-cc <<W
#!/bin/bash
a=(); for x in "\$@"; do case "\$x" in -Werror*) ;; *) a+=("\$x");; esac; done
exec $CLANG "\${a[@]}"
W
chmod +x $PORT/b/jerry-cc
printf 'include(%s)\nset(CMAKE_C_COMPILER %s)\n' "$(cd "$(dirname "$0")/../.." && pwd)/toolchain/ohos-loongarch64.cmake" $PORT/b/jerry-cc > $PORT/b/jerry-tc.cmake
cmake -S "$SRC" -B $B -G Ninja -Wno-dev -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_TOOLCHAIN_FILE=$PORT/b/jerry-tc.cmake \
  -DCMAKE_BUILD_TYPE=MinSizeRel -DJERRY_DEBUGGER=ON -DJERRY_LINE_INFO=ON -DJERRY_CMDLINE=ON -DJERRY_EXT=ON \
  -DJERRY_PORT_DEFAULT=ON -DENABLE_LTO=OFF -DENABLE_STRIP=OFF -DJERRY_LIBM=OFF -DCMAKE_EXE_LINKER_FLAGS=-static
ninja -C $B
qemu-loongarch64 $B/bin/jerry --version || true
