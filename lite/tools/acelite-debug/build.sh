#!/bin/bash
# EXPERIMENTAL: debug build of ACE lite core (libace_lite.so) + JerryScript shared libs for loongarch64,
# ENGINE_DEBUGGER=1; debugger server gated at runtime (default OFF; param/flag file/env, see js_debugger_gate.h),
# binds 127.0.0.1:5001 by default. Compile/link only; NOT ABI-verified vs board.
# Needs: OH 6.1-LTS sources under $OH61SRC (arkui_ace_engine_lite, arkui_ui_lite, graphic_graphic_utils_lite,
# ability_ability_lite, commonlibrary_utils_lite, global_*_lite, hiviewdfx_hilog_lite, startup_init,
# communication_ipc, systemabilitymgr_samgr_lite, third_party_{jerryscript,cJSON,bounds_checking_function}),
# shallow clones of github.com/openharmony/* at tag OpenHarmony-v6.1-LTS.
# Env: BOARD_NEEDED="libui.so libhilog_shared.so ..." (copy NEEDED list from board's readelf -d libace_lite.so)
set -euo pipefail
H=$(cd "$(dirname "$0")" && pwd); PORT=/workspace/hdcd-port
OH61SRC=${OH61SRC:-/workspace/oh61src}; TREE=${OH61TREE:-/workspace/oh61tree}; O=${OUT:-$PORT/b/acelite-la64}
CR=${OHOS_CLANG_ROOT:-/workspace/ohos-clang/clang_linux-x86_64-feef13-20251209}; C=$CR/bin
SR=${OHOS_SYSROOT:-/workspace/hdcd-feas/sysroot-ohos-la64}; T="--target=loongarch64-linux-ohos --sysroot=$SR"
A=$OH61SRC/arkui_ace_engine_lite
# 1) patch ACE + jerry-ext (idempotent)
J=$OH61SRC/third_party_jerryscript
git -C $A apply --check "$H/ace_engine_lite-debugger.patch" 2>/dev/null && git -C $A apply "$H/ace_engine_lite-debugger.patch" || echo "ACE patch already applied"
git -C $J apply --check "$H/jerryscript-debugger-bind.patch" 2>/dev/null && git -C $J apply "$H/jerryscript-debugger-bind.patch" || echo "jerry patch already applied"
# 2) OH-style // tree via symlinks
mkdir -p $TREE/{foundation/arkui,foundation/graphic,foundation/ability,foundation/communication,foundation/systemabilitymgr,base/global,base/hiviewdfx,base/startup,commonlibrary,third_party}
L(){ [ -e "$TREE/$2" ] || ln -s "$OH61SRC/$1" "$TREE/$2"; }
L arkui_ace_engine_lite foundation/arkui/ace_engine_lite; L arkui_ui_lite foundation/arkui/ui_lite
L graphic_graphic_utils_lite foundation/graphic/graphic_utils_lite; L graphic_surface_lite foundation/graphic/surface_lite
L ability_ability_lite foundation/ability/ability_lite; L communication_ipc foundation/communication/ipc
L systemabilitymgr_samgr_lite foundation/systemabilitymgr/samgr_lite; L global_resource_management_lite base/global/resource_management_lite
L global_i18n_lite base/global/i18n_lite; L hiviewdfx_hilog_lite base/hiviewdfx/hilog_lite; L startup_init base/startup/init
L commonlibrary_utils_lite commonlibrary/utils_lite; L third_party_jerryscript third_party/jerryscript
L third_party_cJSON third_party/cJSON; L third_party_bounds_checking_function third_party/bounds_checking_function
# 3) include dirs + sources from ace_lite.gni
mkdir -p $O/obj $O/stub
python3 - "$A/ace_lite.gni" "$TREE" "$O" <<'P'
import re,sys
g=open(sys.argv[1]).read(); tree=sys.argv[2]; o=sys.argv[3]
c={'ACE_LITE_PATH':'//foundation/arkui/ace_engine_lite/frameworks','ACE_LITE_COMMON_PATH':'//foundation/arkui/ace_engine_lite/frameworks/common',
   'NATIVE_ENGINE_PATH':'//foundation/arkui/ace_engine_lite/frameworks/native_engine','MODULE_MANAGER_PATH':'//foundation/arkui/ace_engine_lite/frameworks/module_manager',
   'GRAPHIC_LITE_PATH':'//foundation/arkui/ui_lite'}
def e(x):
    for k,v in c.items(): x=x.replace('$'+k,v).replace('${'+k+'}',v)
    return tree+'/'+x[2:] if x.startswith('//') else x
def b(n): return [e(x) for m in re.finditer(n+r'\s*\+?=\s*\[(.*?)\]',g,re.S) for x in re.findall(r'"([^"]+)"',m.group(1))]
open(o+'/inc.txt','w').write('\n'.join(b('ace_lite_include_dirs')))
open(o+'/src.txt','w').write('\n'.join(x for x in b('ace_lite_sources') if x.endswith(('.c','.cpp'))))
P
I="$(sed 's/^/-I/' $O/inc.txt | tr '\n' ' ') $(sed "s#\${OH61SRC}#$OH61SRC#" $H/extra-includes.txt | sed 's/^/-I/' | tr '\n' ' ')"
# 4) JerryScript PIC static -> shared (debugger on, external context like OH engine.gni)
cat > $PORT/b/jerry-cc <<W
#!/bin/bash
a=(); for x in "\$@"; do case "\$x" in -Werror*) ;; *) a+=("\$x");; esac; done
exec $C/clang "\${a[@]}"
W
chmod +x $PORT/b/jerry-cc
printf 'include(%s)\nset(CMAKE_C_COMPILER %s)\n' "$H/../../toolchain/ohos-loongarch64.cmake" $PORT/b/jerry-cc > $PORT/b/jerry-tc.cmake
JB=$PORT/b/jerry-la64-pic
cmake -S $OH61SRC/third_party_jerryscript -B $JB -G Ninja -Wno-dev -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_TOOLCHAIN_FILE=$PORT/b/jerry-tc.cmake \
  -DCMAKE_BUILD_TYPE=MinSizeRel -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DJERRY_DEBUGGER=ON -DJERRY_LINE_INFO=ON -DJERRY_CMDLINE=OFF \
  -DJERRY_EXT=ON -DJERRY_PORT_DEFAULT=ON -DJERRY_EXTERNAL_CONTEXT=ON -DENABLE_LTO=OFF -DENABLE_STRIP=OFF -DJERRY_LIBM=OFF >/dev/null
ninja -C $JB >/dev/null
# libc.so / board libs: sysroot is static-only -> link against soname stubs (resolved on board at runtime)
echo 'void __ohjs_stub(void){}' > $O/stub/s.c
for so in libc.so ${BOARD_NEEDED:-}; do $C/clang $T -shared -nostdlib -fPIC -o $O/stub/$so $O/stub/s.c -Wl,-soname,$so; done
LS="-nostdlib -L$O/stub -L$CR/lib/loongarch64-linux-ohos -lc"
for n in core ext port-default; do
  $C/clang $T -shared -o $O/libjerry-$n.so -Wl,--whole-archive $JB/lib/libjerry-$n.a -Wl,--no-whole-archive -Wl,-soname,libjerry-$n.so $LS -L$O $([ $n != core ] && echo -ljerry-core)
done
# 5) ACE core objects + libace_lite.so
F="$T -std=c++17 -fPIC -O2 -w -fno-exceptions -fno-rtti -DACE_LITE_FORCE_ENGINE_DEBUGGER -DACE_LITE_DEBUGGER_GATE -DJERRY_DEBUGGER=1 -DJERRY_EXTERNAL_CONTEXT=1"
n=0; rm -f $O/obj/*.o
while read f; do n=$((n+1)); $C/clang++ $F $I -c "$f" -o $O/obj/$n-$(basename "$f").o & [ $((n%8)) = 0 ] && wait; done < $O/src.txt; wait
EXTRA=$(for so in ${BOARD_NEEDED:-}; do echo -l:$so; done)
$C/clang++ $T -shared -o $O/libace_lite.so -Wl,-soname,libace_lite.so $O/obj/*.o -L$O -ljerry-core -ljerry-ext -ljerry-port-default $EXTRA $LS -lc++
$C/llvm-nm -D --undefined-only $O/libace_lite.so | awk '{print $2}' > $O/ace_undefined.txt
echo "objs=$(ls $O/obj | wc -l) undefined=$(wc -l < $O/ace_undefined.txt) debugger_string=$(strings $O/libace_lite.so | grep -c 'please connect to debugger server')"
sha256sum $O/*.so
(cd $O && sha256sum libace_lite.so libjerry-core.so libjerry-ext.so libjerry-port-default.so acedbg-harness > SHA256SUMS)
echo "SHA256SUMS written; BOARD_NEEDED relink: lite/tools/board/relink-board-needed.sh"
# 6) gate harness (static, same jerry PIC libs) for the qemu jsdebug env
$C/clang $T -O2 -static -o $O/acedbg-harness $H/acedbg-harness.c -I$A/frameworks/include/base \
  -I$J/jerry-core/include -I$J/jerry-ext/include -I$J/jerry-port/default/include \
  $JB/lib/libjerry-ext.a $JB/lib/libjerry-core.a $JB/lib/libjerry-port-default.a -lm
echo "harness: $O/acedbg-harness"
