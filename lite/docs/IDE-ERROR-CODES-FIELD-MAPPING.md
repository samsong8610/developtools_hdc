# IDE error-code field mapping (draft, baseline **1.0.0**)

Maps `lite/docs/ide-error-codes.json` fields → suggested IDE consumption surface.  
**Version baseline:** document `version` **1.0.0** (1.x additive-only — see [IDE-ERROR-CODES.md](IDE-ERROR-CODES.md)).  
**全栈:** use this draft when vendoring after IDE **#7** (contract vendor); notify 全栈 to align UI/diagnostics to these fields. No IDE PR from hdc.

Schema: [ide-error-codes.schema.json](ide-error-codes.schema.json) · Data: [ide-error-codes.json](ide-error-codes.json).

## Top-level

| JSON field | Type | IDE surface (draft) | Notes |
|---|---|---|---|
| `version` | semver string | Capability / vendor pin (`major===1`) | Ignore unknown keys within 1.x |
| `$schema` | string | Dev-time validate only | Not required at runtime |
| `protocol` / `hdc_msg_hash` | string | Host/device handshake banner | Cross-check with hdc `-v` |
| `ide_contract` | path string | Link to ports/paths doc | Prefer IDE copy of IDE-CONTRACT |
| `channels` | object | Per-channel matcher tables | Keys: `tconn`,`file`,`bm`,`aa`,`fport`,`shell` |
| `compat` | object (optional) | Policy banner | `1.x-additive-only` |
| `host_version_gate` | object (optional) | Preflight Ver gate copy | Align `check-host-hdc-ver.sh` |

## Per channel (`channels.<name>`)

| JSON field | Type | IDE surface (draft) | Notes |
|---|---|---|---|
| `description` | string | Channel title / tooltip | Localization OK |
| `success_patterns` | string[] | **Success** if stdout/stderr contains any | Substring match; first hit wins |
| `failures` | object[] | Ordered failure matchers | Scan in order after success miss |
| `note` | string (optional) | Footnote in diagnostics panel | e.g. bm/aa `__RC` caveat |

### Channel → IDE command surface

| Channel | Typical IDE action | Primary I/O |
|---|---|---|
| `tconn` | Device connect / refresh targets | `hdc tconn` / list targets |
| `file` | Deploy HAP / push pull | `hdc file send\|recv` |
| `bm` | Install / uninstall / debug flag | `hdc shell bm …` stdout |
| `aa` | Launch / terminate ability | `hdc shell aa …` stdout |
| `fport` | JS debug port forward | `hdc fport` / `fport ls` |
| `shell` | Generic shell / `__RC` | `hdc shell 'cmd; echo __RC=$?'` |

## Per failure (`channels.<name>.failures[]`)

| JSON field | Type | IDE surface (draft) | Notes |
|---|---|---|---|
| `code` | `E######` \| `null` | Error code chip; filter/search | Prefer when `[E00…]` present in text |
| `pattern` | string | Matcher against hdc stdout/stderr | Substring; keep stable in 1.x |
| `when` | string | “Likely cause” blurb | May clarify without changing pattern |
| `ide_hint` | string | **User-facing next step** | Primary remediation string for UI |

### Suggested match algorithm (draft)

1. Run hdc command for channel; capture combined stdout/stderr as `text`.
2. If any `success_patterns[]` substring ∈ `text` → **Success** (stop).
3. Else for each failure in order: if `pattern` ∈ `text` → **Failure**; show `code` (if non-null), `when`, `ide_hint`.
4. Else → **Unknown**; show raw `text` + link to IDE-CONTRACT / this map version.

Do **not** trust hdc process exit alone for `bm` / `aa` / `shell` (see channel `note` / IDE-CONTRACT §3).

## Stability

- **1.x:** additive rows/channels OK; no renames/removes of fields or published `code`/`pattern` semantics (major → 2.0.0).
- IDE should key UI on `channels.*.failures[].code` when set, else on `pattern`.
- Ports/paths remain in IDE-CONTRACT / `ide-contract.manifest.json` — **not** duplicated here.

## 全栈 / #7

After IDE issue **#7** (contract vendor) lands, 全栈 should vendor `ide-error-codes.json` @ **1.0.0** and implement the match algorithm against this field mapping. hdc will not open an IDE PR.

## CI self-check

`lite/ci/check-ide-error-codes-mapping.sh` asserts this document names the same `channels` / `success_patterns` / `failures` field keys as `ide-error-codes.json` (baseline **1.0.0**). Wired via `lite/ci/run-lite-docs-regression.sh` (CI job `ide-error-codes`). Does **not** rename JSON fields (IDE #9 pins an older tip — keep 1.0.0 stable).
