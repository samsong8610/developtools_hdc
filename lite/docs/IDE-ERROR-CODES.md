# IDE channel error codes (hdc lite / Ver 3.2.0c)

Machine-readable companion: [`ide-error-codes.json`](ide-error-codes.json).  
Normative ports/paths: [`IDE-CONTRACT.md`](IDE-CONTRACT.md). Host Ver gate: [`../tools/board/check-host-hdc-ver.sh`](../tools/board/check-host-hdc-ver.sh).

IDE / 全栈: match `pattern` (substring) on hdc stdout/stderr; prefer `code` when `[E00…]` present.

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
