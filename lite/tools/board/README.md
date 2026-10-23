# Board package / lab tools

Scripts in this directory ship in the `ohjs-board-*` handoff package (often under package root or `tools/`).

## Doc entry (package root ↔ source tree)

- [CHANGELOG-ohjs-6.1-lite.md](../../docs/CHANGELOG-ohjs-6.1-lite.md) — thematic v5.0.3 hand-backport guide (`CHANGELOG-ohjs-6.1-lite.md` in package)
- [PORT.md](../../PORT.md) — per-commit list / v5 risk notes (`PORT.md` in package)
- [IDE-CONTRACT.md](../../docs/IDE-CONTRACT.md) — IDE↔device ports/paths (`IDE-CONTRACT.md` in package)

Also: [host/README.md](host/README.md) (host hdc 3.2.0c), [README-ABI.md](README-ABI.md), [README-USB-GADGET.md](README-USB-GADGET.md).

## More docs

- [BACKPORT-v5.0.3.md](../../docs/BACKPORT-v5.0.3.md) — concrete v5 hand-port file list / order
- [qemu-ide README](../../test/qemu-ide/README.md) — no-board smoke + stub aa limits
- [README-ABI.md](README-ABI.md) — pack-debug-libs / from-board-results (offline OK while ABI waits)
- One-shot contract (no board): `../../test/qemu-ide/verify-ide-contract-oneshot.sh`
- CI OSAL matrix: `../../ci/build-osal-matrix.sh` · USB FSM: `./test-usb-gadget-fsm.sh`

## IDE-CONTRACT anti-drift

- Manifest: [`../../docs/ide-contract.manifest.json`](../../docs/ide-contract.manifest.json) (ports 8710/8711/18710, paths `/data/ohjs` `/tmp/ohjs`, marker `debug.<bundle>`).
- Check: `./check-ide-contract-drift.sh` — compares manifest ↔ local `IDE-CONTRACT.md` ↔ IDE repo `docs/IDE-CONTRACT.md` (fetch via `gh`; no IDE PR from hdc).
- **全栈:** add IDE-side half against this manifest after PR #4 sync.

## Host hdc Ver gate

`./check-host-hdc-ver.sh` — requires `Ver: 3.2.0c`; on mismatch prints Linux `host/hdc-linux-x86_64` and Windows DevEco `toolchains\hdc.exe` copy-paste paths. Used by `board-check.ps1` H0 and qemu-ide `verify*.sh`.

## Board recovery (HW OK)

- Handbook: [`../../docs/BOARD-RECOVERY.md`](../../docs/BOARD-RECOVERY.md) — USB collect, ABI zip, G2/G4 UC entry.
- One-click prerelease: `./refresh-board-prerelease.sh` (tip → tar → sha → clobber `ohjs-board-2026-10-29`).
