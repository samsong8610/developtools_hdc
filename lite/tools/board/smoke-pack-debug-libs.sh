#!/bin/bash
# Smoke: identical libs -> zip produced; NO verdict -> refuse to pack.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
PORT=${PORT:-/workspace/hdcd-port}
OURS=${OURS:-$PORT/b/acelite-la64}
TMP=$(mktemp -d /tmp/smoke-pack-XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# --- YES path ---
GOOD="$TMP/good"
mkdir -p "$GOOD"
for so in libace_lite.so libjerry-core.so libjerry-ext.so libjerry-port-default.so; do
  cp -a "$OURS/$so" "$GOOD/$so"
done
OUT_YES="$TMP/out-yes"
mkdir -p "$OUT_YES"
set +e
ZIP_OUT=$("$HERE/pack-debug-libs.sh" --board-libs "$GOOD" --ours "$OURS" --out "$OUT_YES" 2>"$TMP/yes.err")
rc=$?
set -e
ZIP=$(printf '%s
' "$ZIP_OUT" | tail -n1)
echo "YES-path rc=$rc zip='$ZIP'"
tail -5 "$TMP/yes.err" || true
[ "$rc" = 0 ] || { echo "FAIL: expected pack success on identical"; cat "$TMP/yes.err"; exit 1; }
[ -n "$ZIP" ] && [ -f "$ZIP" ] || { echo "FAIL: no zip path"; exit 1; }
case "$ZIP" in
  *.zip) unzip -l "$ZIP" | grep -E 'libace_lite.so|SHA256SUMS|BACKUP-AND-ROLLBACK.md|swap-libs.ps1' >/dev/null ;;
  *.tar.gz) tar -tzf "$ZIP" | grep -E 'libace_lite.so|SHA256SUMS|BACKUP-AND-ROLLBACK.md|swap-libs.ps1' >/dev/null ;;
  *) echo "FAIL: unexpected archive $ZIP"; exit 1 ;;
esac
echo "YES-path contents OK"

# --- NO path (x86 stub as libace_lite) ---
BAD="$TMP/bad"
mkdir -p "$BAD"
cp -a "$GOOD"/* "$BAD/"
# tiny ELF-looking garbage won't match LoongArch — use abi-compare's bad-machine approach:
# copy a host .so if available, else assemble a fake non-LA ELF via printf + our clang targeting x86_64
if command -v cc >/dev/null 2>&1; then
  echo 'int x;' | cc -shared -o "$BAD/libace_lite.so" -x c - 2>/dev/null || \
    echo 'int x;' | cc -m64 -shared -o "$BAD/libace_lite.so" -x c - 2>/dev/null || true
fi
if ! file "$BAD/libace_lite.so" | grep -qi 'loongarch'; then
  :
else
  # force non-match: truncate / replace with text
  printf 'not-an-elf' > "$BAD/libace_lite.so"
fi
OUT_NO="$TMP/out-no"
mkdir -p "$OUT_NO"
set +e
"$HERE/pack-debug-libs.sh" --board-libs "$BAD" --ours "$OURS" --out "$OUT_NO" >"$TMP/no.out" 2>"$TMP/no.err"
rc=$?
set -e
echo "NO-path rc=$rc"
grep -E 'REFUSE|NO' "$TMP/no.err" | head -3 || true
[ "$rc" != 0 ] || { echo "FAIL: expected refuse on bad machine"; cat "$TMP/no.err"; exit 1; }
# no zip should be the final stdout product — ensure no debug-libs archive in out-no
if ls "$OUT_NO"/debug-libs-* >/dev/null 2>&1; then
  echo "FAIL: zip produced despite NO"; ls "$OUT_NO"; exit 1
fi
echo "NO-path refuse OK"
echo "SMOKE PACK PASS"
