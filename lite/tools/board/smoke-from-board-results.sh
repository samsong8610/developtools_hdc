#!/bin/bash
# Smoke from-board-results.sh with fixture zips (identical → pack; bad-machine → stop).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
PORT=${PORT:-/workspace/hdcd-port}
OURS=${OURS:-$PORT/b/acelite-la64}
TMP=$(mktemp -d /tmp/smoke-from-XXXXXX)
trap 'rm -rf "$TMP"' EXIT

mkzip() {
  local name=$1 src=$2
  local d="$TMP/$name"
  mkdir -p "$d/libs"
  cp -a "$src"/* "$d/libs/" 2>/dev/null || true
  # board-check style names also OK; plain libs/ is enough for unpack
  (cd "$d" && zip -q -r "$TMP/$name.zip" .)
  echo "$TMP/$name.zip"
}

# good fixture
GOOD="$TMP/good-libs"
mkdir -p "$GOOD"
for so in libace_lite.so libjerry-core.so libjerry-ext.so libjerry-port-default.so; do
  cp -a "$OURS/$so" "$GOOD/$so"
done
GZ=$(mkzip good "$GOOD")

echo "== good zip =="
WORKG="$TMP/work-good"
set +e
OUT=$("$HERE/from-board-results.sh" "$GZ" --ours "$OURS" --work "$WORKG" 2>"$TMP/good.err")
rc=$?
set -e
ZIP=$(printf '%s\n' "$OUT" | tail -n1)
echo "rc=$rc zip=$ZIP"
grep -E 'NEXT STEPS|Verdict|Packed|STAGE' "$TMP/good.err" | head -20 || true
[ "$rc" = 0 ] || { echo "FAIL good"; cat "$TMP/good.err"; exit 1; }
[ -f "$ZIP" ] || { echo "FAIL no zip"; exit 1; }
[ -f "$WORKG/debug-libs.path" ] || { echo "FAIL no path file"; exit 1; }
echo "good PASS"

# bad fixture
BAD="$TMP/bad-libs"
mkdir -p "$BAD"
cp -a "$GOOD"/* "$BAD/"
printf 'not-an-elf' > "$BAD/libace_lite.so"
BZ=$(mkzip bad "$BAD")
echo "== bad zip =="
WORKB="$TMP/work-bad"
set +e
"$HERE/from-board-results.sh" "$BZ" --ours "$OURS" --work "$WORKB" >"$TMP/bad.out" 2>"$TMP/bad.err"
rc=$?
set -e
echo "rc=$rc"
grep -E 'STOPPED|Verdict|STAGE|REFUSE|NO' "$TMP/bad.err" | head -15 || true
[ "$rc" != 0 ] || { echo "FAIL expected non-zero"; exit 1; }
[ -d "$WORKB" ] || { echo "FAIL work dir missing"; exit 1; }
[ ! -f "$WORKB/debug-libs.path" ] || { echo "FAIL packed despite NO"; exit 1; }
echo "bad PASS (stopped, work kept)"
echo "SMOKE FROM-BOARD-RESULTS PASS"
