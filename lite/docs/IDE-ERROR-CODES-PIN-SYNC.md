# IDE error-codes pin / vendor sync checklist

**Audience:** hdc lite maintainers + 全栈 / IDE after contract vendor lands.  
**Baseline today:** `ide-error-codes.json` **`version` = 1.0.0** — **field names frozen for 1.x**.  
**IDE #9** currently pins an older tip (`5327930b`); do **not** rename/remove 1.0.0 fields until that pin advances and 全栈 re-vendors.

Related: [IDE-ERROR-CODES.md](IDE-ERROR-CODES.md) · [IDE-ERROR-CODES-FIELD-MAPPING.md](IDE-ERROR-CODES-FIELD-MAPPING.md) · schema `ide-error-codes.schema.json`.

## When to use this

Run this checklist when bumping `ide-error-codes.json` within **1.0.x / 1.x** (additive rows, clarifications) **or** when IDE/#9 pin tip moves forward and runtime should pick up a new vendor copy.

Do **not** use this to justify breaking renames — those require **2.0.0** + CHANGELOG callout + coordinated IDE PR (hdc still does not open IDE PRs from this repo by default).

## Pre-flight (keep 1.0.0 stable until ready)

- [ ] Confirm current `version` in `lite/docs/ide-error-codes.json`.
- [ ] Confirm IDE #9 (or successor) pin tip / vendored path on the IDE side.
- [ ] If only docs/CI changed and JSON fields are unchanged → **no vendor bump required**; skip “Publish bump” below.
- [ ] CI green: `bash lite/ci/run-lite-docs-regression.sh` (RESULT=0).

## Allowed 1.x bump shapes

| Bump | Allowed change | Vendor action |
|---|---|---|
| `1.0.0` → `1.0.1` | Typo / `when` / `ide_hint` clarify; same `code`+`pattern` meaning | Optional soft refresh; runtime may ignore if keyed only on major |
| `1.0.x` → `1.1.0` | New failure row, new `success_patterns` entry, new channel, optional top-level key | **Vendor required** — notify 全栈; IDE should accept unknown keys |
| → `2.0.0` | Rename/remove field, remove/repurpose `code`/`pattern` | **Hard stop** — coordinated major; out of scope for “pin sync” alone |

## Publish bump (hdc side)

1. Edit `ide-error-codes.json` (additive only for 1.x); bump `version`.
2. Update `ide-error-codes.schema.json` if new required keys/channels (prefer optional).
3. Update [IDE-ERROR-CODES.md](IDE-ERROR-CODES.md) tables + **Version history** row (Asia/Shanghai date).
4. Update [IDE-ERROR-CODES-FIELD-MAPPING.md](IDE-ERROR-CODES-FIELD-MAPPING.md) if new fields/channels.
5. Run:
   ```bash
   bash lite/ci/validate-ide-error-codes.sh
   bash lite/ci/check-ide-error-codes-mapping.sh
   bash lite/ci/run-lite-docs-regression.sh
   ```
6. Commit (Sam Song) on `ohjs/6.1-lite`; refresh board prerelease if packaging docs.
7. Note tip SHA for 全栈 pin.

## IDE / 全栈 vendor & pin (after #7 / when #9 pin advances)

1. Copy or submodule-pin `ide-error-codes.json` (+ optionally schema) at the agreed tip.
2. Record pin: **tip SHA** + JSON `version` string in IDE notes / lockfile.
3. Runtime: load JSON; match algorithm per FIELD-MAPPING (success_patterns then ordered failures).
4. Treat unknown keys as ignorable (forward compatible within 1.x).
5. Key UI on `channels.*.failures[].code` when non-null, else `pattern`.
6. Do **not** fork field names in the IDE copy.
7. Smoke: feed sample hdc stdout fixtures for tconn / file / bm / aa / fport / shell.
8. Notify hdc lite owner of the new pin tip so the next additive bump can target it.

## Rollback

- If IDE pin breaks: revert vendored JSON to last known-good `version` + tip; file hdc issue with failing channel text.
- hdc keeps prior tip on `ohjs/6.1-lite` history; board package tag `ohjs-board-2026-10-29` can be re-pointed via `refresh-board-prerelease.sh` after fix.

## Current freeze note (2026-10-23 Asia/Shanghai)

- JSON **1.0.0** fields remain stable while IDE #9 pins `5327930b`.
- Mapping CI (`check-ide-error-codes-mapping.sh`) asserts doc ↔ JSON alignment without mutating JSON.
