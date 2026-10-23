# Offline ABI compare (board ACE / Jerry libs)

English one-pager for the board package. Use this **after** `board-check.ps1` returns a `board-results-*.zip` that contains `libs/` (or `path__lib*.so` names).

## Where to put the zip

1. Copy `board-results-YYYYMMDD-HHMMSS.zip` from the Windows machine onto a **Linux** host that has this package (or a checkout of `ohjs/6.1-lite` with `llvm-readelf` / `llvm-nm` from the OHOS clang toolchain).
2. Keep the zip anywhere readable, e.g. `~/Downloads/board-results-….zip`.

Windows-only hosts: `abi-compare.ps1` / `pack-debug-libs.ps1` forward to bash/WSL/Git Bash. If none is available, copy `libs/` to Linux and run the `.sh` scripts there.

## One-shot pipeline (recommended)

```sh
./from-board-results.sh board-results-….zip
# unpack → abi-compare → auto BOARD_NEEDED relink if needed → pack-debug-libs
# On failure: non-zero exit; work dir kept with intermediates.
# Prints NEXT STEPS (download zip, review swap-libs.ps1, -Execute only after confirm).
# Windows: from-board-results.ps1
```

## Which command

```sh
# From the board package directory (or lite/tools/board/ in the repo):
./unpack-board-results.sh board-results-….zip /tmp/br
# prints the libs/ path

./abi-compare.sh --board-results board-results-….zip
# or explicitly:
./abi-compare.sh --board-libs /tmp/br/.../libs --ours /path/to/b/acelite-la64

# Optional Windows wrapper:
powershell -File .\abi-compare.ps1 -BoardResults .\board-results-….zip
```

Reports land in the `--out` directory (default under `/tmp/…`): **`abi-report.md`** and **`abi-report.json`**.

If the report says **CONDITIONAL — relink with BOARD_NEEDED first**:

```sh
BOARD_NEEDED="libui.so libhilog_shared.so …" ./relink-board-needed.sh
./abi-compare.sh --board-libs … --ours …
```

When the verdict is **YES** (or CONDITIONAL after a successful relink), pack pushable libs:

```sh
./pack-debug-libs.sh --board-libs /tmp/br/.../libs --ours /path/to/b/acelite-la64
# → debug-libs-<timestamp>.zip  (libs + SHA256SUMS + BACKUP-AND-ROLLBACK.md + swap-libs.ps1)
```

`swap-libs.ps1` **prints** hdc/shell steps by default. It never remounts unless you pass **`-Execute -DoRemount`**.

## How to interpret YES / CONDITIONAL / NO

| Verdict | Meaning | Action |
|---|---|---|
| **YES — safe to try replace (with backup)** | ELF identity matches; our defined exports are a superset; DT_NEEDED aligned; debugger string / jerry symbols look good. | Backup first, then try replace (prefer `/data` staging). Use `pack-debug-libs.sh` → `swap-libs.ps1`. |
| **CONDITIONAL — relink with BOARD_NEEDED first** | Exports look OK, but the board `libace_lite.so` needs extra sonames we did not link. | Run `relink-board-needed.sh` with the printed `BOARD_NEEDED=…`, rebuild/relink, re-compare. Do **not** push until YES. |
| **CONDITIONAL — review WARN items** | No FAIL, but flags / soname / NEEDED / `.text` size need human review. | Read `abi-report.md` per-check table. Pack only if you accept the WARNs. |
| **NO — do not replace** | Machine/class/ELF mismatch, missing board lib, or defined-export regression (FAIL). | Do **not** replace. Re-pull libs or rebuild. `pack-debug-libs.sh` refuses to pack. |

Always keep a system image for recovery. Details: `JS-DEBUG.md` §B–§D in this package / repo.
