# Host hdc (OpenHarmony 6.1-LTS)

Device `hdcd` in this package speaks protocol **Ver 3.2.0c** with `HDC_MSG_HASH=7fdbc1aa8c5fefaa`.
The **host** client must be the matching **6.1-LTS** hdc.

## Required version

```text
$ hdc -v
Ver: 3.2.0c
```

Any other Ver string → handshake / tconn failures. `board-check.ps1` gate **H0** fails the run if not `3.2.0c`.

## Where to get

| Source | Notes |
|---|---|
| **This package** `host/hdc-linux-x86_64` | Linux x86_64 host client built against the same 6.1-LTS baseline (convenience). `chmod +x` then put on `PATH` or pass `-Hdc`. |
| **OpenHarmony 6.1-LTS release / SDK** | Official host `hdc` / `hdc.exe` from the same LTS tag as device (`OpenHarmony-v6.1-LTS`). |
| **DevEco Studio** | Bundled command-line tools (`hdc` / `hdc.exe`). Confirm `hdc -v` → `Ver: 3.2.0c` before use; newer/older DevEco builds may ship a different Ver. |

Windows: no `hdc.exe` is shipped in this prerelease (not present on the build host). Install from DevEco / OH 6.1-LTS SDK and point `board-check.ps1 -Hdc`.

## Examples (server 8711 / device 8710)

Linux / macOS / WSL:

```bash
export OHOS_HDC_SERVER_PORT=8711
hdc -v                                    # expect: Ver: 3.2.0c
hdc -s 127.0.0.1:8711 start
hdc -s 127.0.0.1:8711 tconn <BOARD_IP>:8710
hdc -s 127.0.0.1:8711 -t <BOARD_IP>:8710 shell 'echo ok; echo __RC=$?'
```

Windows PowerShell:

```powershell
$env:OHOS_HDC_SERVER_PORT = '8711'
hdc -v                                    # expect: Ver: 3.2.0c
hdc -s 127.0.0.1:8711 start
hdc -s 127.0.0.1:8711 tconn <BOARD_IP>:8710
hdc -s 127.0.0.1:8711 -t <BOARD_IP>:8710 shell "echo ok; echo __RC=$?"
# or: .\board-check.ps1 -Target <BOARD_IP>:8710 -Hdc C:\path\to\hdc.exe -ServerPort 8711
```

Qemu-ide on the same machine as the host server: always use **8711** for the host server so it does not collide with device **8710**. See `IDE-CONTRACT.md`.
