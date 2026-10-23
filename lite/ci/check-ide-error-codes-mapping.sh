#!/bin/bash
# Assert IDE-ERROR-CODES-FIELD-MAPPING.md documents the same channels / field keys
# as ide-error-codes.json (vendor baseline 1.0.0). Does not mutate JSON.
# Exit 0 = aligned; 1 = drift.
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
JSON=${JSON:-$ROOT/lite/docs/ide-error-codes.json}
MAP=${MAP:-$ROOT/lite/docs/IDE-ERROR-CODES-FIELD-MAPPING.md}
SCHEMA=${SCHEMA:-$ROOT/lite/docs/ide-error-codes.schema.json}
R=0
pass(){ echo "[PASS] $*"; }
fail(){ echo "[FAIL] $*"; R=1; }

echo "==== check-ide-error-codes-mapping $(date '+%Y-%m-%d %H:%M:%S %z') ===="
[ -f "$JSON" ] || { echo "missing $JSON"; exit 2; }
[ -f "$MAP" ] || { echo "missing $MAP"; exit 2; }

python3 - "$JSON" "$MAP" "$SCHEMA" << 'PY'
import json, re, sys
from pathlib import Path
jpath, mpath, spath = sys.argv[1:4]
doc = json.load(open(jpath, encoding="utf-8"))
mapping = open(mpath, encoding="utf-8").read()
R = 0

def ok(msg):
    print(f"[PASS] {msg}")
def bad(msg):
    global R
    print(f"[FAIL] {msg}")
    R = 1

# version pin
ver = str(doc.get("version", ""))
if ver != "1.0.0":
    bad(f"JSON version={ver} (expected 1.0.0 — #9 pin / stable vendor baseline)")
else:
    ok("JSON version 1.0.0")
if "1.0.0" not in mapping:
    bad("FIELD-MAPPING.md missing version 1.0.0 baseline mention")
else:
    ok("FIELD-MAPPING mentions 1.0.0")

# top-level keys that mapping must name (stable 1.0.0)
for key in ("version", "protocol", "hdc_msg_hash", "ide_contract", "channels"):
    if key not in doc:
        bad(f"JSON missing top-level {key}")
    if f"`{key}`" not in mapping and f"| `{key}`" not in mapping and key not in mapping:
        bad(f"FIELD-MAPPING missing top-level field `{key}`")
    else:
        ok(f"top-level `{key}` documented")

# channels
chs = doc.get("channels") or {}
required_ch = ("tconn", "file", "bm", "aa", "fport")
for name in required_ch:
    if name not in chs:
        bad(f"JSON missing channels.{name}")
        continue
    # mapping must list channel name
    if not re.search(rf"`{name}`|{name}", mapping):
        bad(f"FIELD-MAPPING missing channel {name}")
    else:
        ok(f"channel {name} in mapping")
    ch = chs[name]
    for fk in ("description", "success_patterns", "failures"):
        if fk not in ch:
            bad(f"JSON channels.{name} missing {fk}")
        if f"`{fk}`" not in mapping:
            bad(f"FIELD-MAPPING missing field `{fk}`")
    # at least one failure with required keys
    fails = ch.get("failures") or []
    if not fails:
        bad(f"channels.{name}.failures empty")
    else:
        f0 = fails[0]
        for fk in ("pattern", "when", "ide_hint"):
            if fk not in f0:
                bad(f"JSON channels.{name}.failures[0] missing {fk}")
        if "code" not in f0:
            bad(f"JSON channels.{name}.failures[0] missing code (may be null)")
        ok(f"channels.{name} failure shape OK")

# failure field names must appear in mapping table
for fk in ("code", "pattern", "when", "ide_hint"):
    if f"`{fk}`" not in mapping:
        bad(f"FIELD-MAPPING missing failure field `{fk}`")
    else:
        ok(f"failure field `{fk}` documented")

# success_patterns documented
if "`success_patterns`" not in mapping:
    bad("FIELD-MAPPING missing `success_patterns`")
else:
    ok("`success_patterns` documented")

# shell optional but if in JSON must be in mapping
if "shell" in chs and "shell" not in mapping:
    bad("JSON has shell channel but FIELD-MAPPING omits it")
elif "shell" in chs:
    ok("shell channel covered")

# schema file exists and lists same required channels if present
if Path(spath).is_file():
    sch = json.load(open(spath, encoding="utf-8"))
    req = ((sch.get("properties") or {}).get("channels") or {}).get("required") or []
    for name in req:
        if name not in chs:
            bad(f"schema requires {name} but JSON lacks it")
        if name not in mapping:
            bad(f"schema channel {name} not in FIELD-MAPPING")
    ok(f"schema required channels checked ({len(req)})")
else:
    bad(f"schema missing: {spath}")

# JSON path referenced from mapping
if "ide-error-codes.json" not in mapping:
    bad("FIELD-MAPPING should link ide-error-codes.json")
else:
    ok("FIELD-MAPPING links ide-error-codes.json")

sys.exit(R)
PY
R=$?
echo "RESULT=$R"
exit $R
