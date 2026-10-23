#!/bin/bash
# Anti-drift: hdc ide-contract.manifest.json + local IDE-CONTRACT.md vs IDE repo docs/IDE-CONTRACT.md.
# Does NOT modify the IDE repo. 全栈 can add an IDE-side half that diffs against this manifest.
#
# Usage:
#   ./check-ide-contract-drift.sh
#   IDE_CONTRACT_REF=main ./check-ide-contract-drift.sh
#   IDE_CONTRACT_FILE=/path/to/IDE-CONTRACT.md ./check-ide-contract-drift.sh
#
# Fetch via gh api (preferred) or local clone. Exit 0 = no drift on required keys.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
LITE=$(cd "$HERE/../.." && pwd)          # lite/
ROOT=$(cd "$LITE/.." && pwd)             # developtools_hdc
MANIFEST=${MANIFEST:-$LITE/docs/ide-contract.manifest.json}
LOCAL_MD=${LOCAL_MD:-$LITE/docs/IDE-CONTRACT.md}
IDE_REPO=${IDE_REPO:-samsong8610/ohos-lite-js-ide}
IDE_REF=${IDE_CONTRACT_REF:-main}
R=0
pass(){ echo "[PASS] $*"; }
fail(){ echo "[FAIL] $*"; R=1; }
warn(){ echo "[WARN] $*"; }

echo "==== check-ide-contract-drift $(date '+%Y-%m-%d %H:%M:%S %z') ===="
echo "manifest=$MANIFEST"
echo "local_md=$LOCAL_MD"

[ -f "$MANIFEST" ] || { echo "missing manifest"; exit 2; }
[ -f "$LOCAL_MD" ] || { echo "missing local IDE-CONTRACT.md"; exit 2; }

# --- A) manifest keys present in local MD ---
python3 - "$MANIFEST" "$LOCAL_MD" << 'PY'
import json, re, sys
man, md_path = sys.argv[1], sys.argv[2]
m = json.load(open(man))
text = open(md_path, encoding="utf-8").read()
R = 0

def need(label, needle):
    global R
    if needle in text or str(needle) in text:
        print(f"[PASS] local MD has {label}: {needle}")
    else:
        # allow bare number for ports
        print(f"[FAIL] local MD missing {label}: {needle}")
        R = 1

ports = m["ports"]
need("device_hdcd_tcp", str(ports["device_hdcd_tcp"]))
need("host_hdc_server", str(ports["host_hdc_server"]))
need("jsdebug_host_bridge", str(ports["jsdebug_host_bridge"]))
need("OHOS_HDC_SERVER_PORT", ports["host_hdc_server_env"])
paths = m["paths"]
need("ide_ace_dir", "/data/ohjs")
need("hap_push", "/tmp/ohjs/app.hap")
need("debug_marker", "debug.<bundle>")
need("tmp_dir", "/tmp/ohjs")
need("hilog_cap", "hilog.cap")
need("__RC", "__RC")
sys.exit(R)
PY
A=$?
[ "$A" = 0 ] && pass "manifest ↔ local IDE-CONTRACT.md" || fail "manifest ↔ local IDE-CONTRACT.md"

# --- B) fetch IDE repo contract ---
IDE_TMP=$(mktemp /tmp/ide-contract-XXXX.md)
fetched=0
if [ -n "${IDE_CONTRACT_FILE:-}" ] && [ -f "$IDE_CONTRACT_FILE" ]; then
  cp -a "$IDE_CONTRACT_FILE" "$IDE_TMP"
  fetched=1
  echo "using IDE_CONTRACT_FILE=$IDE_CONTRACT_FILE"
elif command -v gh >/dev/null 2>&1; then
  # try main, then docs/sync-ide-contract (PR #4 branch)
  for ref in "$IDE_REF" docs/sync-ide-contract main; do
    if gh api "repos/$IDE_REPO/contents/docs/IDE-CONTRACT.md?ref=$ref" \
        --jq '.content' 2>/dev/null | base64 -d > "$IDE_TMP" 2>/dev/null \
        && grep -q 'IDE' "$IDE_TMP" 2>/dev/null; then
      echo "fetched $IDE_REPO@$ref:docs/IDE-CONTRACT.md"
      fetched=1
      IDE_REF=$ref
      break
    fi
  done
fi
if [ "$fetched" != 1 ]; then
  # local clone fallback
  for p in /workspace/ohos-lite-js-ide /tmp/ohos-lite-js-ide; do
    if [ -f "$p/docs/IDE-CONTRACT.md" ]; then
      cp -a "$p/docs/IDE-CONTRACT.md" "$IDE_TMP"
      echo "using local clone $p/docs/IDE-CONTRACT.md"
      fetched=1
      break
    fi
  done
fi
if [ "$fetched" != 1 ]; then
  warn "could not fetch IDE IDE-CONTRACT.md — skip cross-repo diff (local check still counts)"
  echo "RESULT=$R (ide_fetch=miss)"
  rm -f "$IDE_TMP"
  exit $R
fi

# --- C) required strings in IDE MD (same keys as manifest) ---
python3 - "$MANIFEST" "$IDE_TMP" << 'PY'
import json, sys
m = json.load(open(sys.argv[1]))
text = open(sys.argv[2], encoding="utf-8").read()
R = 0
def need(label, needle):
    global R
    if str(needle) in text:
        print(f"[PASS] IDE MD has {label}: {needle}")
    else:
        print(f"[FAIL] IDE MD missing {label}: {needle}")
        R = 1
ports = m["ports"]
need("device_hdcd_tcp", ports["device_hdcd_tcp"])
need("host_hdc_server", ports["host_hdc_server"])
need("jsdebug_host_bridge", ports["jsdebug_host_bridge"])
need("path /data/ohjs", "/data/ohjs")
need("path /tmp/ohjs", "/tmp/ohjs")
need("marker debug.<bundle>", "debug.<bundle>")
need("hap app.hap", "app.hap")
sys.exit(R)
PY
C=$?
[ "$C" = 0 ] && pass "manifest ↔ IDE repo IDE-CONTRACT.md (@$IDE_REF)" || fail "manifest ↔ IDE repo (drift / PR #4 out of date?)"

# --- D) structural: strip sync banner, compare port/path tables loosely ---
python3 - "$LOCAL_MD" "$IDE_TMP" << 'PY'
import re, sys
def norm(path):
    t = open(path, encoding="utf-8").read()
    t = re.sub(r"<!--.*?-->", "", t, flags=re.S)
    # keep only lines with ports/paths markers
    keys = []
    for line in t.splitlines():
        if any(x in line for x in ("8710", "8711", "18710", "/data/ohjs", "/tmp/ohjs", "debug.<bundle>", "app.hap", "__RC")):
            keys.append(re.sub(r"\s+", " ", line.strip()))
    return keys
a, b = norm(sys.argv[1]), norm(sys.argv[2])
# every hdc key line's critical tokens should appear somewhere in IDE
tokens = {"8710", "8711", "18710", "/data/ohjs", "/tmp/ohjs", "debug.<bundle>", "__RC"}
ide = "\n".join(b)
R = 0
for tok in sorted(tokens):
    if tok in ide:
        print(f"[PASS] shared token {tok}")
    else:
        print(f"[FAIL] IDE missing token {tok}")
        R = 1
sys.exit(R)
PY
D=$?
[ "$D" = 0 ] && pass "shared tokens hdc ↔ IDE" || fail "shared tokens drift"

rm -f "$IDE_TMP"
echo "NOTE: 全栈 — add IDE-side diff against lite/docs/ide-contract.manifest.json (or this script's keys)."
echo "PR #4 sync check: IDE docs/IDE-CONTRACT.md must keep ports/paths/markers above; re-sync from hdc when manifest bumps."
echo "RESULT=$R"
exit $R
