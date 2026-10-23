#!/bin/bash
# Offline ABI comparison: board ACE/jerry .so (from board-results zip) vs our debug build.
#
# Usage:
#   abi-compare.sh --board-libs DIR [--ours DIR] [--out DIR]
#   abi-compare.sh --board-results board-results.zip|DIR [--ours DIR] [--out DIR]
#
# Defaults: --ours = $PORT/b/acelite-la64, --out = ./abi-report-<stamp>
# Writes abi-report.md + abi-report.json under --out.
# Exit 0 = recommendation safe-to-try (or no FAIL); 1 = FAIL present; 2 = usage/tooling error.
#
# Windows: run under WSL / Git Bash, or use abi-compare.ps1 (unpacks zip, then calls this via bash).
set -eu

PORT=${PORT:-/workspace/hdcd-port}
CR=${OHOS_CLANG_ROOT:-/workspace/ohos-clang/clang_linux-x86_64-feef13-20251209}
pick_tool() {
  for c in "$@"; do
    if [ -x "$c" ]; then echo "$c"; return; fi
    if command -v "$c" >/dev/null 2>&1; then command -v "$c"; return; fi
  done
  return 1
}
READELF=${READELF:-$(pick_tool "$CR/bin/llvm-readelf" llvm-readelf readelf || true)}
NM=${NM:-$(pick_tool "$CR/bin/llvm-nm" llvm-nm nm || true)}
[ -n "$READELF" ] && [ -n "$NM" ] || { echo "need llvm-readelf/readelf and llvm-nm/nm" >&2; exit 2; }

BOARD_LIBS=; OURS=$PORT/b/acelite-la64; OUT=; BOARD_RESULTS=
while [ $# -gt 0 ]; do
  case "$1" in
    --board-libs) BOARD_LIBS=$2; shift 2 ;;
    --ours) OURS=$2; shift 2 ;;
    --out) OUT=$2; shift 2 ;;
    --board-results) BOARD_RESULTS=$2; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
HERE=$(cd "$(dirname "$0")" && pwd)
if [ -n "$BOARD_RESULTS" ]; then
  BOARD_LIBS=$("$HERE/unpack-board-results.sh" "$BOARD_RESULTS")
fi
[ -n "$BOARD_LIBS" ] && [ -d "$BOARD_LIBS" ] || { echo "--board-libs DIR or --board-results ZIP required" >&2; exit 2; }
[ -d "$OURS" ] || { echo "--ours not a directory: $OURS" >&2; exit 2; }
OUT=${OUT:-$PWD/abi-report-$(date +%Y%m%d-%H%M%S)}
mkdir -p "$OUT"

# ---- helpers ----
basename_so() {
  # board-check.ps1 stores libs as path__with__underscores__libace_lite.so
  local b; b=$(basename "$1")
  if [[ "$b" == *__* ]]; then
    local last=${b##*__}
    case "$last" in *.so|*.so.*) echo "$last"; return ;; esac
  fi
  echo "$b"
}

canon_name() {
  # map libfoo.so.1.2 -> libfoo.so for matching
  local n=$1
  echo "$n" | sed -E 's/\.so(\.[0-9]+)*$/.so/'
}

elf_field() { # $1=file $2=label regex
  "$READELF" -h "$1" 2>/dev/null | sed -n "s/^[[:space:]]*$2:[[:space:]]*//p" | head -1
}
elf_flags() { "$READELF" -h "$1" 2>/dev/null | sed -n 's/^[[:space:]]*Flags:[[:space:]]*//p' | head -1; }
dyn_soname() { "$READELF" -d "$1" 2>/dev/null | sed -n 's/.*Library soname: \[\(.*\)\]/\1/p' | head -1; }
dyn_needed() { "$READELF" -d "$1" 2>/dev/null | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p' | sort -u; }
text_size() {
  "$READELF" -S "$1" 2>/dev/null | sed -nE 's/^.*\.text[[:space:]]+PROGBITS[[:space:]]+[0-9a-fA-Fx]+[[:space:]]+[0-9a-fA-Fx]+[[:space:]]+([0-9a-fA-Fx]+).*/\1/p' | head -1
}
text_size_dec() {
  local h; h=$(text_size "$1")
  [ -n "$h" ] || { echo 0; return; }
  printf '%d\n' "$((16#${h#0x}))" 2>/dev/null || echo 0
}
defined_syms() { "$NM" -D --defined-only --format=posix "$1" 2>/dev/null | awk '{print $1}' | grep -v '^$' | sort -u; }
undef_syms()   { "$NM" -D --undefined-only --format=posix "$1" 2>/dev/null | awk '{print $1}' | grep -v '^$' | sort -u; }
has_string() { strings "$1" 2>/dev/null | grep -qF "$2"; }
json_escape() { python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()[:-1] if False else sys.argv[1]))' "$1"; }

# Index board libs by canonical basename (board-check.ps1 may use path__libace_lite.so names)
declare -A BOARD_FILE
while IFS= read -r -d '' f; do
  bn=$(basename_so "$f")
  cn=$(canon_name "$bn")
  case "$cn" in
    libace_*.so|libjerry*.so|libjerry-*.so) BOARD_FILE[$cn]=$f ;;
  esac
done < <(find "$BOARD_LIBS" -type f \( -name '*.so' -o -name '*.so.*' \) -print0 2>/dev/null)

OURS_LIBS=()
for n in libace_lite.so libjerry-core.so libjerry-ext.so libjerry-port-default.so; do
  [ -f "$OURS/$n" ] && OURS_LIBS+=("$n")
done
[ ${#OURS_LIBS[@]} -gt 0 ] || { echo "no libs in --ours $OURS" >&2; exit 2; }

# Collect results as lines: LIB|CHECK|STATUS|DETAIL
RES=$OUT/_results.tsv
: > "$RES"
add() { # lib check status detail
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$RES"
}

compare_one() {
  local name=$1 ours=$2 board=$3
  local om bm oc bc ot bt of bf os bs
  om=$(elf_field "$ours" 'Machine'); bm=$(elf_field "$board" 'Machine')
  oc=$(elf_field "$ours" 'Class');   bc=$(elf_field "$board" 'Class')
  ot=$(elf_field "$ours" 'Type');    bt=$(elf_field "$board" 'Type')
  of=$(elf_flags "$ours"); bf=$(elf_flags "$board")
  os=$(dyn_soname "$ours"); bs=$(dyn_soname "$board")
  os=${os:-$name}; bs=${bs:-$(basename_so "$board")}

  if [ "$om" = "$bm" ] && [ "$oc" = "$bc" ] && [[ "$ot" == *DYN* && "$bt" == *DYN* ]]; then
    add "$name" "elf-identity" PASS "Machine=$om Class=$oc Type=DYN"
  else
    add "$name" "elf-identity" FAIL "ours=($om/$oc/$ot) board=($bm/$bc/$bt)"
  fi
  if [ "$of" = "$bf" ]; then
    add "$name" "elf-flags" PASS "$of"
  else
    add "$name" "elf-flags" WARN "ours=[$of] board=[$bf]"
  fi
  if [ "$os" = "$bs" ]; then
    add "$name" "soname" PASS "$os"
  else
    add "$name" "soname" WARN "ours=$os board=$bs"
  fi

  local on bn
  on=$(dyn_needed "$ours" | tr '\n' ' ')
  bn=$(dyn_needed "$board" | tr '\n' ' ')
  dyn_needed "$ours"  > "$OUT/$name.ours.needed"
  dyn_needed "$board" > "$OUT/$name.board.needed"
  local only_ours only_board
  only_ours=$(comm -23 "$OUT/$name.ours.needed" "$OUT/$name.board.needed" | tr '\n' ' ')
  only_board=$(comm -13 "$OUT/$name.ours.needed" "$OUT/$name.board.needed" | tr '\n' ' ')
  if [ -z "$only_ours" ] && [ -z "$only_board" ]; then
    add "$name" "needed" PASS "identical: $on"
  elif [ -n "$only_board" ] && [ -z "$only_ours" ]; then
    add "$name" "needed" WARN "board-only NEEDED (relink with BOARD_NEEDED): $only_board"
  elif [ -n "$only_ours" ] && [ -z "$only_board" ]; then
    add "$name" "needed" WARN "ours-only NEEDED (board may lack them): $only_ours"
  else
    add "$name" "needed" WARN "ours-only=[$only_ours] board-only=[$only_board]"
  fi

  defined_syms "$ours"  > "$OUT/$name.ours.def"
  defined_syms "$board" > "$OUT/$name.board.def"
  undef_syms "$ours"    > "$OUT/$name.ours.und"
  undef_syms "$board"   > "$OUT/$name.board.und"
  local miss extra
  miss=$(comm -13 "$OUT/$name.ours.def" "$OUT/$name.board.def" | wc -l)
  extra=$(comm -23 "$OUT/$name.ours.def" "$OUT/$name.board.def" | wc -l)
  local miss_n extra_n
  miss_n=$(comm -13 "$OUT/$name.ours.def" "$OUT/$name.board.def" | head -20 | tr '\n' ' ')
  extra_n=$(comm -23 "$OUT/$name.ours.def" "$OUT/$name.board.def" | head -10 | tr '\n' ' ')
  if [ "$miss" -eq 0 ]; then
    add "$name" "exports-defined" PASS "ours is superset (board=$("$NM" -D --defined-only "$board" 2>/dev/null | wc -l) ours=$(wc -l < "$OUT/$name.ours.def") extra=$extra)"
  else
    add "$name" "exports-defined" FAIL "board exports missing from ours: $miss (e.g. $miss_n)"
  fi
  # undefined: informational; board may pull from different libs
  local und_ours und_board und_only
  und_ours=$(wc -l < "$OUT/$name.ours.und")
  und_board=$(wc -l < "$OUT/$name.board.und")
  und_only=$(comm -23 "$OUT/$name.ours.und" "$OUT/$name.board.und" | wc -l)
  add "$name" "undefined" INFO "ours=$und_ours board=$und_board ours-only=$und_only (see $name.ours.und)"

  local ts_o ts_b
  ts_o=$(text_size_dec "$ours"); ts_b=$(text_size_dec "$board")
  if [ "$ts_b" -eq 0 ] || [ "$ts_o" -eq 0 ]; then
    add "$name" "text-size" INFO "ours=$ts_o board=$ts_b"
  else
    local pct=$(( (ts_o - ts_b) * 100 / ts_b ))
    local apct=$pct; [ $apct -lt 0 ] && apct=$((-apct))
    if [ $apct -le 50 ]; then
      add "$name" "text-size" PASS "ours=$ts_o board=$ts_b (${pct}%)"
    else
      add "$name" "text-size" WARN "ours=$ts_o board=$ts_b (${pct}% — large delta, different build flags?)"
    fi
  fi

  if has_string "$ours" 'please connect to debugger server'; then
    if has_string "$board" 'please connect to debugger server'; then
      add "$name" "debugger-string" PASS "present in both"
    else
      add "$name" "debugger-string" INFO "ours has debugger string; board does not (expected for release board)"
    fi
  else
    add "$name" "debugger-string" INFO "ours lacks debugger string"
  fi

  # jerry debugger symbols (relevant for jerry-ext and ace_lite which imports them)
  local jsyms="jerryx_debugger_tcp_create jerryx_debugger_tcp_create_bind jerryx_debugger_ws_create jerryx_debugger_after_connect jerry_debugger_stop"
  local oj bj
  oj=; bj=
  for s in $jsyms; do
    grep -qx "$s" "$OUT/$name.ours.def" && oj="$oj $s"
    grep -qx "$s" "$OUT/$name.board.def" && bj="$bj $s"
  done
  if [ "$name" = "libjerry-ext.so" ]; then
    if echo "$oj" | grep -q tcp_create_bind; then
      add "$name" "jerry-debugger-syms" PASS "ours:$oj"
    else
      add "$name" "jerry-debugger-syms" FAIL "ours missing jerryx_debugger_tcp_create_bind (debug gate needs it)"
    fi
  elif [ "$name" = "libace_lite.so" ]; then
    # ace imports them as undefined
    local need_bind=
    grep -qx jerryx_debugger_tcp_create_bind "$OUT/$name.ours.und" && need_bind=1
    if [ -n "$need_bind" ]; then
      add "$name" "jerry-debugger-syms" INFO "imports tcp_create_bind (needs matching libjerry-ext.so)"
    else
      add "$name" "jerry-debugger-syms" INFO "does not import tcp_create_bind"
    fi
  else
    add "$name" "jerry-debugger-syms" INFO "n/a for $name"
  fi

  # sizes / sha
  add "$name" "file-meta" INFO "ours=$(stat -c%s "$ours")B sha=$(sha256sum "$ours"|awk '{print $1}') | board=$(stat -c%s "$board")B sha=$(sha256sum "$board"|awk '{print $1}')"
}

MISSING_BOARD=()
for name in "${OURS_LIBS[@]}"; do
  if [ -z "${BOARD_FILE[$name]:-}" ]; then
    MISSING_BOARD+=("$name")
    add "$name" "present-on-board" WARN "not found under $BOARD_LIBS — skipped"
    continue
  fi
  add "$name" "present-on-board" PASS "${BOARD_FILE[$name]}"
  compare_one "$name" "$OURS/$name" "${BOARD_FILE[$name]}"
done

# Board-only interesting libs (native_engine / module_manager) — INFO
for name in libace_native_engine.so libace_module_manager.so; do
  if [ -n "${BOARD_FILE[$name]:-}" ]; then
    add "$name" "board-only-lib" INFO "pulled from board (we do not ship this); NEEDED=$(dyn_needed "${BOARD_FILE[$name]}" | tr '\n' ' ')"
    defined_syms "${BOARD_FILE[$name]}" > "$OUT/$name.board.def" || true
  fi
done

# ---- recommendation ----
n_fail=$(awk -F'\t' '$3=="FAIL"{c++} END{print c+0}' "$RES")
n_warn=$(awk -F'\t' '$3=="WARN"{c++} END{print c+0}' "$RES")
n_pass=$(awk -F'\t' '$3=="PASS"{c++} END{print c+0}' "$RES")
rec=; rec_detail=
if [ "$n_fail" -gt 0 ]; then
  rec="NO — do not replace"
  rec_detail="One or more FAIL checks (ELF identity or missing board exports). Fix the build or obtain matching sources before any swap."
elif echo "${MISSING_BOARD[*]-}" | grep -q libace_lite; then
  rec="NO — board libace_lite.so not in the zip"
  rec_detail="Re-run board-check.ps1 with broader -LibSearchRoots, or pull the libs manually."
elif [ "$n_warn" -gt 0 ]; then
  board_needed=$(awk -F'\t' '$2=="needed" && $3=="WARN" && $4 ~ /board-only NEEDED/{sub(/.*: /,""); gsub(/[ ]+$/,""); print; exit}' "$RES")
  if [ -n "$board_needed" ]; then
    rec="CONDITIONAL — relink with BOARD_NEEDED first"
    rec_detail="Board libace_lite.so needs: $board_needed. Run: BOARD_NEEDED=\"$board_needed\" $HERE/relink-board-needed.sh   then re-run this compare. ABI exports look OK."
  else
    rec="CONDITIONAL — review WARN items"
    rec_detail="No FAIL, but WARN on flags/soname/NEEDED/text-size. Read the report; a careful try on a writable copy is possible after backup."
  fi
else
  rec="YES — safe to try replace (with backup)"
  rec_detail="ELF identity matches; our defined symbols are a superset of the board's; NEEDED aligned. Still: backup, remount caveats, and feature-flag/snapshot risks in JS-DEBUG.md §B apply. Prefer a writable /data copy test before touching /system."
fi

# ---- write reports ----
{
  echo "# ABI comparison report"
  echo
  echo "- Generated: $(date -Iseconds)"
  echo "- Board libs: \`$BOARD_LIBS\`"
  echo "- Ours: \`$OURS\`"
  echo "- Tooling: READELF=$READELF NM=$NM"
  echo "- Counts: PASS=$n_pass WARN=$n_warn FAIL=$n_fail"
  echo
  echo "## Recommendation"
  echo
  echo "**$rec**"
  echo
  echo "$rec_detail"
  echo
  echo "## Per-check results"
  echo
  echo "| Library | Check | Status | Detail |"
  echo "|---|---|---|---|"
  awk -F'\t' '{printf "| `%s` | %s | **%s** | %s |\n",$1,$2,$3,$4}' "$RES"
  echo
  echo "## BOARD_NEEDED hint"
  echo
  if [ -f "$OUT/libace_lite.so.board.needed" ]; then
    echo "Board libace_lite.so NEEDED:"
    echo '```'
    cat "$OUT/libace_lite.so.board.needed"
    echo '```'
    echo "Ours:"
    echo '```'
    cat "$OUT/libace_lite.so.ours.needed"
    echo '```'
    only_b=$(comm -13 "$OUT/libace_lite.so.ours.needed" "$OUT/libace_lite.so.board.needed" | tr '\n' ' ')
    if [ -n "$only_b" ]; then
      echo
      echo "Suggested relink:"
      echo '```sh'
      echo "BOARD_NEEDED=\"$only_b\" $HERE/relink-board-needed.sh"
      echo '```'
    fi
  else
    echo "(libace_lite.so not compared)"
  fi
  echo
  echo "## Missing board exports (first 50)"
  echo
  if [ -f "$OUT/libace_lite.so.ours.def" ] && [ -f "$OUT/libace_lite.so.board.def" ]; then
    missc=$(comm -13 "$OUT/libace_lite.so.ours.def" "$OUT/libace_lite.so.board.def" | wc -l)
    if [ "$missc" -eq 0 ]; then echo "_None — ours is a superset._"
    else echo '```'; comm -13 "$OUT/libace_lite.so.ours.def" "$OUT/libace_lite.so.board.def" | head -50; echo '```'; fi
  else
    echo "_n/a_"
  fi
  echo
  echo "## Our sha256"
  echo
  echo '```'
  (cd "$OURS" && sha256sum libace_lite.so libjerry-*.so 2>/dev/null)
  echo '```'
} > "$OUT/abi-report.md"

python3 - "$RES" "$OUT/abi-report.json" "$BOARD_LIBS" "$OURS" "$rec" "$rec_detail" "$n_pass" "$n_warn" "$n_fail" <<'PY'
import json,sys
res,out,bl,ours,rec,det,np,nw,nf = sys.argv[1:10]
rows=[]
for line in open(res,encoding='utf-8'):
    lib,chk,st,detl = line.rstrip('\n').split('\t',3)
    rows.append({"library":lib,"check":chk,"status":st,"detail":detl})
json.dump({
  "board_libs": bl, "ours": ours,
  "counts": {"PASS": int(np), "WARN": int(nw), "FAIL": int(nf)},
  "recommendation": {"verdict": rec, "detail": det},
  "results": rows,
}, open(out,'w',encoding='utf-8'), indent=2)
print(out)
PY

echo "Wrote $OUT/abi-report.md"
echo "Wrote $OUT/abi-report.json"
echo "Recommendation: $rec"
# exit code
if [ "$n_fail" -gt 0 ]; then exit 1; fi
exit 0
