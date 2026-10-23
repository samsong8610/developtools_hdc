#!/bin/bash
# Unpack a board-results-*.zip from board-check.ps1 and print the libs/ directory.
# Usage: unpack-board-results.sh board-results-YYYYMMDD-HHMMSS.zip [dest-dir]
#        unpack-board-results.sh board-results-DIR/            # already unpacked
# Prints the absolute path of libs/ on stdout (last line); other messages on stderr.
set -euo pipefail
in=${1:?usage: $0 board-results.zip|board-results-DIR [dest]}
dest=${2:-}
if [ -d "$in" ]; then
  root=$(cd "$in" && pwd)
elif [ -f "$in" ]; then
  dest=${dest:-$(mktemp -d /tmp/board-results-XXXXXX)}
  mkdir -p "$dest"
  case "$in" in
    *.zip) unzip -qo "$in" -d "$dest" ;;
    *.tar.gz|*.tgz) tar xzf "$in" -C "$dest" ;;
    *) echo "unknown archive: $in" >&2; exit 2 ;;
  esac
  # zip may contain a top-level board-results-* dir or the files themselves
  if [ -d "$dest/libs" ]; then root=$dest
  else
    root=$(find "$dest" -type d -name 'libs' -printf '%h\n' 2>/dev/null | head -1)
    root=${root:-$dest}
  fi
else
  echo "not found: $in" >&2; exit 2
fi
libs=
for c in "$root/libs" "$root"/*/libs; do
  [ -d "$c" ] || continue
  libs=$(cd "$c" && pwd); break
done
if [ -z "$libs" ]; then
  # board-check names files like path__to__libace_lite.so — accept a flat dir of *.so
  if ls "$root"/*.so >/dev/null 2>&1 || ls "$root"/*/*.so >/dev/null 2>&1; then
    libs=$root
  else
    echo "no libs/ under $root" >&2; exit 1
  fi
fi
echo "unpacked root: $root" >&2
echo "summary:      $root/Summary.txt" >&2
echo "libs:         $libs  ($(find "$libs" -name '*.so*' | wc -l) .so files)" >&2
printf '%s\n' "$libs"
