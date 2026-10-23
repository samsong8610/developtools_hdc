#!/bin/bash
# One-click: tip → pack handoff tar + sha256 + change summary → upload/clobber GitHub prerelease.
#
# Usage (from developtools_hdc checkout, or any cwd):
#   ./lite/tools/board/refresh-board-prerelease.sh
#   TAG=ohjs-board-2026-10-29 PORT_ROOT=/workspace/hdcd-port \
#     ./lite/tools/board/refresh-board-prerelease.sh
#   DRY_RUN=1 ./lite/tools/board/refresh-board-prerelease.sh   # pack only, no gh upload
#   NOTES_ONLY=1 ./…   # edit release notes from existing local tar (rare)
#
# Env:
#   TAG          prerelease tag (default ohjs-board-2026-10-29)
#   PORT_ROOT    tree with hdcd.stripped + host hdc (default: parent of repo or /workspace/hdcd-port)
#   OUT_DIR      where handoff-<date>/ and tar land (default: PORT_ROOT)
#   REPO         owner/name (default samsong8610/developtools_hdc)
#   HAND_NAME    directory/tar basename (default handoff-2026-10-29)
#   DRY_RUN=1    do not gh release upload/edit
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/../../.." && pwd)   # developtools_hdc
LITE=$(cd "$HERE/../.." && pwd)
TAG=${TAG:-ohjs-board-2026-10-29}
REPO=${REPO:-samsong8610/developtools_hdc}
HAND_NAME=${HAND_NAME:-handoff-2026-10-29}
DATE_LABEL=${DATE_LABEL:-2026-10-29}

# PORT_ROOT: binaries + previous handoff
if [ -z "${PORT_ROOT:-}" ]; then
  if [ -d "$REPO_ROOT/../handoff-2026-10-29" ] || [ -f "$REPO_ROOT/../b/out/hdcd.stripped" ]; then
    PORT_ROOT=$(cd "$REPO_ROOT/.." && pwd)
  elif [ -d /workspace/hdcd-port ]; then
    PORT_ROOT=/workspace/hdcd-port
  else
    PORT_ROOT=$REPO_ROOT/..
  fi
fi
OUT_DIR=${OUT_DIR:-$PORT_ROOT}
H="$OUT_DIR/$HAND_NAME"

cd "$REPO_ROOT"
TIP=$(git rev-parse HEAD)
SHORT=$(git rev-parse --short=8 HEAD)
BRANCH=$(git rev-parse --abbrev-ref HEAD)
BIN_COMMIT=${BIN_COMMIT:-c143133ecac36aad301b7694217e253504bfb233}

echo "==== refresh-board-prerelease $(date '+%Y-%m-%d %H:%M:%S %z') ===="
echo "repo=$REPO_ROOT tip=$SHORT branch=$BRANCH"
echo "PORT_ROOT=$PORT_ROOT OUT=$H TAG=$TAG"

# Resolve binaries
HDCD_BIN=${HDCD_BIN:-}
for c in "$HDCD_BIN" "$PORT_ROOT/b/out/hdcd.stripped" "$PORT_ROOT/$HAND_NAME/hdcd.stripped" "$H/hdcd.stripped"; do
  [ -n "${c:-}" ] && [ -f "$c" ] && HDCD_BIN=$c && break
done
HDC_HOST=${HDC_HOST:-}
for c in "$HDC_HOST" "$PORT_ROOT/$HAND_NAME/host/hdc-linux-x86_64" "$PORT_ROOT/hdc-host" "$H/host/hdc-linux-x86_64"; do
  [ -n "${c:-}" ] && [ -f "$c" ] && HDC_HOST=$c && break
done
[ -f "$HDCD_BIN" ] || { echo "missing hdcd.stripped (set HDCD_BIN or PORT_ROOT)"; exit 2; }
[ -f "$HDC_HOST" ] || { echo "missing host hdc (set HDC_HOST)"; exit 2; }

# Previous docs_commit for change summary
PREV=
if [ -f "$H/MANIFEST" ]; then
  PREV=$(awk '/^docs_commit:/{print $2; exit}' "$H/MANIFEST" || true)
fi
if [ -z "$PREV" ] && command -v gh >/dev/null 2>&1; then
  PREV=$(gh release view "$TAG" -R "$REPO" --json body -q .body 2>/dev/null | \
    sed -n 's/.*tip `\([0-9a-f]\{7,40\}\)`.*/\1/p' | head -1 || true)
fi
PREV=${PREV:-fd008a0652e92913617e446a056f3076ab947b27}

mkdir -p "$H"/{host,etc,ci/workflows,tools}

# --- copy docs ---
cp -a "$LITE/docs/IDE-CONTRACT.md" "$LITE/docs/CHANGELOG-ohjs-6.1-lite.md" \
  "$LITE/docs/BACKPORT-v5.0.3.md" "$LITE/docs/JS-DEBUG.md" \
  "$LITE/docs/IDE-ERROR-CODES.md" "$LITE/docs/ide-error-codes.json" \
  "$LITE/docs/ide-error-codes.schema.json" \
  "$LITE/docs/ide-contract.manifest.json" \
  "$LITE/docs/SOAK-FAILURE-ARCHIVE.md" \
  "$LITE/docs/IDE-ERROR-CODES-FIELD-MAPPING.md" \
  "$REPO_ROOT/lite/PORT.md" \
  "$H/"
# Recovery handbook if present
[ -f "$LITE/docs/BOARD-RECOVERY.md" ] && cp -a "$LITE/docs/BOARD-RECOVERY.md" "$H/"
# Keep existing BOARD-CHECKLIST if we don't have source in repo
if [ ! -f "$H/BOARD-CHECKLIST.md" ] && [ -f "$PORT_ROOT/$HAND_NAME/BOARD-CHECKLIST.md" ]; then
  cp -a "$PORT_ROOT/$HAND_NAME/BOARD-CHECKLIST.md" "$H/"
fi
# Prefer repo copy if we add one later
[ -f "$LITE/docs/BOARD-CHECKLIST.md" ] && cp -a "$LITE/docs/BOARD-CHECKLIST.md" "$H/"
[ -f "$LITE/tools/board/BOARD-CHECKLIST.md" ] && cp -a "$LITE/tools/board/BOARD-CHECKLIST.md" "$H/"

# --- board tools ---
cp -a "$LITE/tools/board/"*.sh "$LITE/tools/board/"*.ps1 "$H/tools/" 2>/dev/null || true
cp -a "$LITE/tools/board/README.md" "$LITE/tools/board/README-ABI.md" \
  "$LITE/tools/board/README-USB-GADGET.md" "$H/tools/" 2>/dev/null || true
# Root convenience copies (package layout)
for f in board-check.ps1 abi-compare.sh abi-compare.ps1 from-board-results.sh from-board-results.ps1 \
         pack-debug-libs.sh relink-board-needed.sh unpack-board-results.sh setup-usb-gadget.sh \
         check-host-hdc-ver.sh check-ide-contract-drift.sh refresh-board-prerelease.sh \
         run-qemu-ide-ci.sh; do
  [ -f "$LITE/tools/board/$f" ] && cp -a "$LITE/tools/board/$f" "$H/"
  [ -f "$LITE/ci/$f" ] && cp -a "$LITE/ci/$f" "$H/"
done
cp -a "$LITE/ci/run-qemu-ide-ci.sh" "$H/" 2>/dev/null || true
cp -a "$LITE/ci/run-qemu-ide-ci.sh" "$H/tools/" 2>/dev/null || true
cp -a "$LITE/ci/validate-ide-error-codes.sh" "$H/ci/" 2>/dev/null || true
cp -a "$LITE/ci/build-osal-matrix.sh" "$H/ci/" 2>/dev/null || true
cp -a "$LITE/ci/README.md" "$H/ci/" 2>/dev/null || true
cp -a "$REPO_ROOT/.github/workflows/lite-qemu-ide.yml" "$H/ci/workflows/" 2>/dev/null || true
cp -a "$REPO_ROOT/.github/workflows/lite-osal.yml" "$H/ci/workflows/" 2>/dev/null || true

# qemu-ide key scripts
for f in verify-ide-contract-oneshot.sh soak-ide-contract.sh smoke-qemu-edges.sh \
         smoke-stability.sh verify-contract.sh; do
  [ -f "$LITE/test/qemu-ide/$f" ] && cp -a "$LITE/test/qemu-ide/$f" "$H/tools/"
done
cp -a "$LITE/test/qemu-ide/verify-ide-contract-oneshot.sh" "$H/" 2>/dev/null || true
cp -a "$LITE/test/qemu-ide/soak-ide-contract.sh" "$H/" 2>/dev/null || true
cp -a "$LITE/test/qemu-ide/README.md" "$H/qemu-ide-README.md" 2>/dev/null || true
cp -a "$LITE/docs/ide-error-codes.json" "$LITE/docs/ide-error-codes.schema.json" \
  "$LITE/docs/IDE-ERROR-CODES.md" "$H/tools/" 2>/dev/null || true

# binaries + para + host readme (skip cp if already the destination file)
mkdir -p "$H/host"
copy_bin() {
  local src=$1 dst=$2
  local rs rd
  rs=$(readlink -f "$src" 2>/dev/null || echo "$src")
  rd=$(readlink -f "$dst" 2>/dev/null || echo "$dst")
  if [ -f "$dst" ] && [ "$rs" = "$rd" ]; then
    echo "keep $dst"
  else
    cp -a "$src" "$dst"
  fi
  chmod +x "$dst" 2>/dev/null || true
}
copy_bin "$HDCD_BIN" "$H/hdcd.stripped"
copy_bin "$HDC_HOST" "$H/host/hdc-linux-x86_64"
cp -a "$LITE/tools/board/host/README.md" "$H/host/README.md"
cp -a "$LITE/etc/hdcd.para" "$H/etc/hdcd.para" 2>/dev/null || \
  cp -a "$PORT_ROOT/$HAND_NAME/etc/hdcd.para" "$H/etc/hdcd.para"
# osal readme
[ -f "$LITE/osal/README.md" ] && cp -a "$LITE/osal/README.md" "$H/osal-README.md"

BINSHA=$(sha256sum "$H/hdcd.stripped" | awk '{print $1}')

# --- change summary ---
SUMMARY=$(mktemp)
{
  echo "Changes since ${PREV:0:8} → $SHORT:"
  git log --oneline "${PREV}..${TIP}" 2>/dev/null | head -40 || git log --oneline -15
} | tee "$SUMMARY"

# --- README ---
if [ ! -f "$H/README.md" ]; then
  if [ -f "$PORT_ROOT/$HAND_NAME/README.md" ]; then
    cp -a "$PORT_ROOT/$HAND_NAME/README.md" "$H/README.md"
  else
    echo "# hdcd Lite board package" > "$H/README.md"
  fi
fi
python3 - "$H/README.md" "$SHORT" "$TIP" "$BINSHA" << 'PY'
import re, sys
from pathlib import Path
path, short, full, binsha = sys.argv[1:5]
t = Path(path).read_text(encoding="utf-8")
t = re.sub(r"tip `[0-9a-f]+`", f"tip `{short}`", t)
t = re.sub(r"(\| 源码分支 \| tip `)[0-9a-f]+(`)", rf"\g<1>{short}\2", t)
t = re.sub(r"(\| 完整 commit \| `)[0-9a-f]+(`)", rf"\g<1>{full}\2", t)
t = re.sub(r"(\| 本包二进制 sha256 \| `)[0-9a-f]+(`)", rf"\g<1>{binsha}\2", t)
# Ensure recovery / refresh / schema links
extras = [
    ("`BOARD-RECOVERY.md`", "Board recovery handbook — USB collect, ABI zip, G2/G4 UC entry (when 2K0300 HW OK)"),
    ("`refresh-board-prerelease.sh`", "One-click tip→tar→sha→clobber prerelease `ohjs-board-2026-10-29`"),
    ("`ide-error-codes.schema.json`", "JSON Schema for ide-error-codes.json (version 1.x stable fields)"),
]
for name, desc in extras:
    key = name.strip("`")
    if key not in t and name not in t:
        lines = t.splitlines()
        out = []
        done = False
        for line in lines:
            out.append(line)
            if not done and line.startswith("| `IDE-CONTRACT.md` |"):
                out.append(f"| {name} | {desc} |")
                done = True
        if not done:
            out.append(f"| {name} | {desc} |")
        t = "\n".join(out) + "\n"
# Top link to recovery if missing
if "BOARD-RECOVERY.md" in t and "## Board recovery" not in t and "上板恢复" not in t:
    anchor = "\n> **上板恢复 / HW 就绪入口：** [`BOARD-RECOVERY.md`](BOARD-RECOVERY.md)（USB 采集、ABI zip、G2/G4 UC）。\n"
    # after first heading block
    parts = t.split("\n", 2)
    if len(parts) >= 2:
        t = parts[0] + "\n" + parts[1] + anchor + (parts[2] if len(parts) > 2 else "")
Path(path).write_text(t, encoding="utf-8")
print("README updated", short)
PY

# --- MANIFEST + SHA256SUMS ---
python3 - "$H" "$TIP" "$BIN_COMMIT" << 'PY'
import hashlib, sys
from pathlib import Path
root = Path(sys.argv[1])
full, bin_commit = sys.argv[2], sys.argv[3]
files = []
for p in sorted(root.rglob("*")):
    if p.is_file() and p.name not in ("MANIFEST", "SHA256SUMS"):
        rel = p.relative_to(root).as_posix()
        data = p.read_bytes()
        files.append((rel, hashlib.sha256(data).hexdigest(), len(data)))
lines = [
    "# hdcd board package (IDE / full-stack)",
    "# Generated: 2026-10-23 Asia/Shanghai",
    "",
    "name: hdcd-lite-handoff",
    "date: 2026-10-29",
    "protocol: Ver 3.2.0c",
    "hdc_msg_hash: 7fdbc1aa8c5fefaa",
    "branch: ohjs/6.1-lite",
    f"commit: {bin_commit}   # hdcd.stripped",
    f"docs_commit: {full}",
    f"tools_commit: {full}",
    "upstream_base: 51794b3efb6b8eaf2b06776403c30e1b91c6b4fd (OpenHarmony-v6.1-LTS)",
    "osal_backend: linux (default); liteos_a=stub",
    "default_listen_port: 8710",
    "",
    "files:",
]
for rel, sha, sz in files:
    lines += [f"  - path: {rel}", f"    sha256: {sha}", f"    size_bytes: {sz}"]
(root / "MANIFEST").write_text("\n".join(lines) + "\n", encoding="utf-8")
sums = [f"{hashlib.sha256((root / 'MANIFEST').read_bytes()).hexdigest()}  MANIFEST"]
sums += [f"{sha}  {rel}" for rel, sha, sz in files]
(root / "SHA256SUMS").write_text("\n".join(sums) + "\n", encoding="utf-8")
print(f"MANIFEST files={len(files)}")
PY

# --- tar + sha ---
TAR="$OUT_DIR/${HAND_NAME}.tar.gz"
TARSHA_FILE="$OUT_DIR/${HAND_NAME}.tar.gz.sha256"
SUMS="$OUT_DIR/SHA256SUMS"
rm -f "$TAR"
tar -C "$OUT_DIR" -czf "$TAR" "$HAND_NAME"
TARSHA=$(sha256sum "$TAR" | awk '{print $1}')
echo "$TARSHA  ${HAND_NAME}.tar.gz" | tee "$TARSHA_FILE"
printf '%s  %s\n%s  %s\n' \
  "$TARSHA" "${HAND_NAME}.tar.gz" \
  "$(sha256sum "$TARSHA_FILE" | awk '{print $1}')" "${HAND_NAME}.tar.gz.sha256" > "$SUMS"
echo "TARSHA=$TARSHA"

CHANGE_BULLETS=$(git log --oneline "${PREV}..${TIP}" 2>/dev/null | head -12 | sed 's/^/- /' || true)
NOTES=$(cat <<NOTE
Board package refreshed $(date '+%Y-%m-%d') Asia/Shanghai (tip ${SHORT}).

tar.gz sha256: \`${TARSHA}\`

${CHANGE_BULLETS}

Packed by \`lite/tools/board/refresh-board-prerelease.sh\`.
NOTE
)

if [ "${DRY_RUN:-0}" = 1 ]; then
  echo "DRY_RUN=1 — skip gh upload"
  echo "$NOTES"
  echo "RESULT=0 tar=$TAR"
  exit 0
fi

command -v gh >/dev/null || { echo "gh not found; tar ready at $TAR"; exit 3; }
gh release upload "$TAG" "$TAR" "$TARSHA_FILE" "$SUMS" -R "$REPO" --clobber
gh release edit "$TAG" -R "$REPO" --notes "$NOTES"
echo "uploaded $TAG"
echo "RESULT=0 tip=$SHORT tar_sha=$TARSHA"
