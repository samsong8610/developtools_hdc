# Example: soak `LAST_FAILURE` layout

Illustrative tree (not from a real failure). Matches what `soak-ide-contract.sh` writes under `OUT_DIR`.

```text
soak-last-failure/           # stands in for lite/test/qemu-ide-soak/
  SUMMARY.txt
  LAST_FAILURE -> failures/fail-iter-003/
  failures/
    fail-iter-003/
      iter.log
      SUMMARY.txt
      REPRO.txt
```

See [SOAK-FAILURE-ARCHIVE.md](../../SOAK-FAILURE-ARCHIVE.md).
