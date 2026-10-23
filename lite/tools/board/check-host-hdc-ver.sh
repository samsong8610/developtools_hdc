#!/bin/bash
# Gate: host hdc must be Ver 3.2.0c (matches device hdcd / IDE-CONTRACT).
# On mismatch, print copy-paste install/path hints (Windows DevEco + Linux package).
#
# Usage:
#   ./check-host-hdc-ver.sh              # uses HDC or hdc on PATH
#   HDC=/path/to/hdc ./check-host-hdc-ver.sh
#   ./check-host-hdc-ver.sh /path/to/hdc
#
# Exit 0 = Ver 3.2.0c; exit 1 = mismatch / missing.
set -u
HDC_BIN=${1:-${HDC:-$(command -v hdc 2>/dev/null || true)}}
HERE=$(cd "$(dirname "$0")" && pwd)
HOST_README=${HOST_README:-$HERE/host/README.md}

print_hints() {
  cat <<'HINTS'

──── host hdc must be Ver: 3.2.0c (HDC_MSG_HASH=7fdbc1aa8c5fefaa) ────

Linux (this board package):
  chmod +x ./host/hdc-linux-x86_64
  ./host/hdc-linux-x86_64 -v          # expect: Ver: 3.2.0c
  export PATH="$(pwd)/host:$PATH"
  # or: export HDC="$(pwd)/host/hdc-linux-x86_64"

Windows — DevEco Studio (no hdc.exe in this prerelease):
  {DevEco}\sdk\default\openharmony\toolchains\hdc.exe
  {DevEco}\sdk\default\hms\toolchains\hdc.exe   # some installs; prefer openharmony\toolchains

  Examples:
  C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe
  D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe

  PowerShell check:
    $hdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
    & $hdc -v                         # expect: Ver: 3.2.0c
    $env:OHOS_HDC_SERVER_PORT = '8711'

OpenHarmony 6.1 public SDK (Windows/Linux toolchains tree):
  {sdk_root}\...\toolchains\hdc.exe   /   .../toolchains/hdc
  See: https://gitee.com/openharmony/docs (hdc guide — Obtaining hdc)

Do not use a mismatched host client against this hdcd — handshake/tconn will fail.
Full paths: lite/tools/board/host/README.md  (package: host/README.md)
HINTS
  if [ -f "$HOST_README" ]; then
    echo "(host README present: $HOST_README)"
  fi
}

if [ -z "$HDC_BIN" ]; then
  echo "[FAIL] host hdc not found (set HDC= or pass path)"
  print_hints
  exit 1
fi
if [ ! -x "$HDC_BIN" ] && [ -f "$HDC_BIN" ]; then
  chmod +x "$HDC_BIN" 2>/dev/null || true
fi
if [ ! -x "$HDC_BIN" ] && ! command -v "$HDC_BIN" >/dev/null 2>&1; then
  echo "[FAIL] host hdc not executable: $HDC_BIN"
  print_hints
  exit 1
fi

vo=$("$HDC_BIN" -v 2>&1 || true)
echo "hdc=$HDC_BIN"
echo "hdc -v: $vo"
if echo "$vo" | grep -qE 'Ver:\s*3\.2\.0c'; then
  echo "[PASS] host hdc Ver 3.2.0c"
  exit 0
fi
echo "[FAIL] host hdc must be Ver: 3.2.0c (got: ${vo:-<empty>})"
print_hints
exit 1
