# IDE channel error codes (hdc lite / Ver 3.2.0c)

Machine-readable companion: [`ide-error-codes.json`](ide-error-codes.json).  
IDE field mapping (draft, 1.0.0): [`IDE-ERROR-CODES-FIELD-MAPPING.md`](IDE-ERROR-CODES-FIELD-MAPPING.md) — 全栈 after #7.  
Pin / vendor sync checklist: [`IDE-ERROR-CODES-PIN-SYNC.md`](IDE-ERROR-CODES-PIN-SYNC.md) (after IDE #9 pin advances; keep 1.0.0 fields stable until then).
Normative ports/paths: [`IDE-CONTRACT.md`](IDE-CONTRACT.md). Host Ver gate: [`../tools/board/check-host-hdc-ver.sh`](../tools/board/check-host-hdc-ver.sh).

IDE / 全栈: match `pattern` (substring) on hdc stdout/stderr; prefer `code` when `[E00…]` present.

## Schema / version / IDE vendor

| Item | Value |
|---|---|
| Document | [`ide-error-codes.json`](ide-error-codes.json) |
| Schema | [`ide-error-codes.schema.json`](ide-error-codes.schema.json) |
| `version` | **1.0.0** (semver of this map; field names frozen for 1.x) |
| CI | `lite/ci/validate-ide-error-codes.sh` (also in `lite-osal.yml` / `lite-qemu-ide.yml`) |

**Stable fields (do not rename in 1.x):** `version`, `protocol`, `hdc_msg_hash`, `ide_contract`, `channels`, per-channel `description` / `success_patterns` / `failures`, per-failure `code` / `pattern` / `when` / `ide_hint`. Optional: `note`, `host_version_gate`, `description` (doc blurb).

**全栈 / IDE:** when this schema is accepted as stable, **notify 全栈 to vendor** the JSON (after IDE issues **#6 / #7**). Prefer vendoring `ide-error-codes.json` + checking `version`; do not fork field names so #7 contract vendor stays compatible. Breaking renames → bump to **2.0.0** and call out in CHANGELOG.


## 1.x compatibility policy

**Additive only within 1.x.** Allowed without a major bump:

- Add a new channel, failure row, `success_patterns` entry, or optional top-level key.
- Clarify `when` / `ide_hint` text (same `code` + `pattern` meaning).
- Patch bumps: `1.0.0` → `1.0.1` (doc/typo); minor: `1.1.0` (new rows/channels).

**Not allowed in 1.x** (requires **2.0.0** + explicit callout):

- Rename or remove a field (`channels`, `failures`, `code`, `pattern`, `when`, `ide_hint`, …).
- Remove a published `code` or change its semantic meaning / primary `pattern`.
- Repurpose an existing channel name.

IDE / 全栈 vendors should pin on `version` major `1` and treat unknown keys as ignorable. Manifest / IDE-CONTRACT field names stay independent unless a coordinated bump is required.

## Version history

| version | Date (Asia/Shanghai) | Notes |
|---|---|---|
| **1.0.0** | 2026-10-23 | Initial map: tconn / file / bm / aa / fport / shell; `$schema` + CI validate. Field names frozen for 1.x. Ready to vendor after IDE #6/#7 notify. |


## tconn

| Code | Pattern | When | IDE hint |
|---|---|---|---|
| — | `Connect failed` | Wrong port / hdcd down / used **18710** for G2 | `tconn <ip>:8710`; server `OHOS_HDC_SERVER_PORT=8711` |
| E001005 | `[E001005] Device not found or connected` | No target / removed | Re-tconn; pass `-t` |
| E001104 | `[E001104]:IP address incorrect` | Bad address | `host:port` |
| E001100 | `[E001100]Invalid port` | Bad port | Device **8710** |
| E000001 | `[E000001]:…version is too low` | Host too old | Install Ver **3.2.0c** (DevEco / `host/hdc-linux-x86_64`) |

## file send/recv

| Code | Pattern | When | IDE hint |
|---|---|---|---|
| — | `FileTransfer finish` | **Success** | — |
| E005102 | `[E005102] Remote path:` | Path missing / invalid | `mkdir -p /tmp/ohjs`; HAP → `/tmp/ohjs/app.hap` |
| E005005 | `[E005005] Error create directory` | Cannot mkdir | Writable `/tmp/ohjs` or `/data/ohjs` |
| E005008 | `[E005008] Operation not allowed` | Blocked path | Stay under contract paths |

## bm / aa (stdout text; `__RC` often 0)

| Channel | Success substring | Failure substring | Note |
|---|---|---|---|
| bm install | `install success !` | install failed / error | Do not trust hdc exit |
| bm uninstall | `uninstall success !` | — | |
| bm set -s disable | `success` | — | debug firmware |
| aa start | `receive command: start` | `Failed to run the command.` | Normative fail text |

Always: `hdc shell '<cmd>; echo __RC=$?'` and parse `__RC`.

## fport

| Pattern | When | IDE hint |
|---|---|---|
| `Forwardport result:OK` | Success | |
| `Forwardport result:Failed` | Bind / task fail | `fport ls` / `rm`; jerry must listen |
| `Forward parament failed` | Bad argv | `fport tcp:<host> tcp:<dev>` |

## Cross-links

- Ports **8710 / 8711 / 18710**, paths `/data/ohjs`, `/tmp/ohjs`, marker `debug.<bundle>` → [IDE-CONTRACT.md](IDE-CONTRACT.md) + [ide-contract.manifest.json](ide-contract.manifest.json)
- Host mismatch hints → [host/README.md](../tools/board/host/README.md)
