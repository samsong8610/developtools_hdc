# Soak failure archive (qemu-ide)

When `soak-ide-contract.sh` fail-fasts, it writes a **minimal repro bundle** under the soak output directory.

## Path convention

| Path | Meaning |
|---|---|
| `lite/test/qemu-ide-soak/` | Default `OUT_DIR` (override with `OUT_DIR=`) |
| `…/SUMMARY.txt` | Pass/fail lines for all iters attempted |
| `…/iter-NNN.log` | Full oneshot log for iteration NNN |
| `…/failures/fail-iter-NNN/` | **Failure archive** (first failing iter) |
| `…/failures/fail-iter-NNN/iter.log` | Copy of failing iter log |
| `…/failures/fail-iter-NNN/SUMMARY.txt` | SUMMARY at fail time |
| `…/failures/fail-iter-NNN/REPRO.txt` | Env + minimal repro steps |
| `…/failures/fail-iter-NNN/qemu-ide-contract*.log` | Nested contract logs if present |
| `…/LAST_FAILURE` | Symlink → latest `failures/fail-iter-NNN` |

Override root: `OUT_DIR=/path/to/drop ./soak-ide-contract.sh`.


## Concrete sample (`LAST_FAILURE` layout)

Checked-in example (synthetic): [`examples/soak-last-failure/`](examples/soak-last-failure/).

```text
examples/soak-last-failure/
├── SUMMARY.txt
├── LAST_FAILURE → failures/fail-iter-003/
└── failures/
    └── fail-iter-003/
        ├── iter.log      # failing oneshot log
        ├── SUMMARY.txt   # soak summary at fail-fast
        └── REPRO.txt     # env + minimal repro steps
```

After a real soak fail:

```bash
ls -la lite/test/qemu-ide-soak/LAST_FAILURE
cat lite/test/qemu-ide-soak/LAST_FAILURE/REPRO.txt
# zip for bug report:
#   cd lite/test/qemu-ide-soak && zip -r /tmp/soak-fail.zip LAST_FAILURE failures/fail-iter-*
```

## What to attach in a bug report

Drop or zip **`failures/fail-iter-NNN/`** (or follow `LAST_FAILURE`). Include tip from `REPRO.txt`.

## CI

`lite/ci/run-qemu-ide-ci.sh` runs soak; workflow `.github/workflows/lite-qemu-ide.yml` uploads:

```text
lite/test/qemu-ide-soak/
```

That artifact includes `failures/` when soak fails. Job fails (must PASS when qemu env available); download the artifact for repro.

## Minimal local repro

```bash
# After a failure:
cat lite/test/qemu-ide-soak/LAST_FAILURE/REPRO.txt
SKIP_START=1 lite/test/qemu-ide/verify-ide-contract-oneshot.sh
# or:
N=1 SKIP_START=1 OUT_DIR=/tmp/soak-repro lite/test/qemu-ide/soak-ide-contract.sh
```
