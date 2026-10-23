# qemu-ide — host-side IDE / hdcd lab (no real board)

Runs static **loongarch64** `hdcd` under `qemu-loongarch64` (user mode) on TCP **8710**.
Host hdc server: **`OHOS_HDC_SERVER_PORT=8711`**. See [`../../docs/IDE-CONTRACT.md`](../../docs/IDE-CONTRACT.md).

## Quick start (no board)

```sh
./run-qemu-hdcd.sh start
export OHOS_HDC_SERVER_PORT=8711
hdc -s 127.0.0.1:8711 tconn 127.0.0.1:8710
./smoke-stability.sh          # reconnect / file send / parallel shell / verify-contract
./smoke-qemu-edges.sh         # large/reconnect/concurrent + NEG port/path/debug.*
N=20 ./soak-ide-contract.sh   # oneshot ×N fail-fast (logs qemu-ide-soak/)
./verify.sh                   # bm/aa/hilogcat + __RC (uses stubs)
./run-qemu-hdcd.sh stop
```

USB gadget (host/board script, dry-run without UDC):

```sh
../../tools/board/setup-usb-gadget.sh --dry-run
../../tools/board/setup-usb-gadget.sh --check   # exit 1 if no configfs/UDC — expected on this box
```

## Known limits — stub `aa` / `bm` / `hilogcat`

Stubs live in `stubs/` and are installed into the fakeroot PATH by `run-qemu-hdcd.sh`.

| Stub | Behaves like | **Not** real |
|---|---|---|
| `bm` | stdout strings (`install success !`, …) | No HAP parse beyond config.json presence in fakeroot bundles |
| `aa` | stdout (`receive command: start`, `Failed to run…`); always process exit 0 | No AbilityMgr / JS runtime; “running” is a fakeroot file; **no** real app lifecycle |
| `hilogcat` | streams / appends to fakeroot log | No hilogd; not device log levels |

Implications for IDE UAT against qemu-ide:

- Deploy/launch **text matchers** work; do not treat stub `aa start` as proof of ACE/jerry on device.
- Marker / jsdebug flows use separate `jsdebug` mode + real jerry/harness — not the `aa` stub.
- Stability smoke does **not** depend on `aa` (shell + file send only).

## Scripts

| Script | Role |
|---|---|
| `run-qemu-hdcd.sh` | start/stop/status; `jsdebug` netns mode |
| `smoke-stability.sh` | reconnect ×N, 1–5 MiB file send, parallel shell, `verify-contract` |
| `verify-contract.sh` | 8710 PASS / 18710 FAIL (start-only); `/data/ohjs` + clean `debug.*` |
| **`verify-ide-contract-oneshot.sh`** | **One-shot** IDE-CONTRACT: tconn/file/fport/marker + nested verify-contract |
| `verify.sh` | G2 bm/aa/hilogcat (stubs) |
| `verify-jsdebug*.sh` / `verify-acedbg-gate.sh` | G4 debugger (needs jerry / harness) |
