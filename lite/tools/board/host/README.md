# Host hdc (OpenHarmony 6.1-LTS)

Device `hdcd` in this package speaks protocol **Ver 3.2.0c** with `HDC_MSG_HASH=7fdbc1aa8c5fefaa`.
The **host** client must be the matching **6.1-LTS** hdc.

## Required version

```text
$ hdc -v
Ver: 3.2.0c
```

Any other Ver string → handshake / tconn failures. `board-check.ps1` gate **H0** fails the run if not `3.2.0c`.

`hdc version` is an alias of `-v` on some builds; expect the same `Ver: 3.2.0c` line.

## Where to get

| Source | Notes |
|---|---|
| **This package** `host/hdc-linux-x86_64` | Linux x86_64 host client built against the same 6.1-LTS baseline (convenience). `chmod +x` then put on `PATH` or pass `-Hdc`. |
| **DevEco Studio (Windows / macOS)** | Bundled OpenHarmony SDK toolchains — see paths below. Confirm `hdc -v` before use. |
| **OpenHarmony 6.1 public SDK** | `ohos-sdk-windows_linux-public.tar.gz` from the 6.1-Release mirror; after unpack, take `hdc.exe` / `hdc` from the Windows / Linux **toolchains** tree. |

### Windows — exact relative paths (no `hdc.exe` in this prerelease)

This build host has **no** redistributable Windows `hdc.exe` (no SDK cache, no mingw cross-build). We **do not** ship a vendor SDK binary. Install from DevEco or the public OH SDK, then verify version.

**DevEco Studio** (typical install roots; adjust drive / “Huawei” vs “DevEco-Studio”):

```text
{DevEco}\sdk\default\openharmony\toolchains\hdc.exe
{DevEco}\sdk\default\hms\toolchains\hdc.exe          # some installs; prefer openharmony\toolchains
```

Examples:

```text
C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe
D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe
```

Add that `toolchains` directory to `PATH`, or pass the full path to `board-check.ps1 -Hdc`.

**OpenHarmony public SDK** (Windows half of `ohos-sdk-windows_linux-public.tar.gz`, 6.1-Release):

```text
{sdk_root}\...\toolchains\hdc.exe
```

Official obtain note: [hdc guide — Obtaining hdc](https://gitee.com/openharmony/docs/blob/master/en/device-dev/subsystems/subsys-toolchain-hdc-guide.md) (“copy **hdc.exe** from **toolchains**”).

### Version check (must pass before board work)

```powershell
# PowerShell
& 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe' -v
# expect exactly:
# Ver: 3.2.0c

$env:OHOS_HDC_SERVER_PORT = '8711'
hdc -v
hdc checkserver
```

```bash
# Linux (package binary or SDK)
./host/hdc-linux-x86_64 -v    # Ver: 3.2.0c
```

If `hdc -v` is not `Ver: 3.2.0c`, stop — do not use that host client against this `hdcd`.

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
$hdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
& $hdc -v                                 # expect: Ver: 3.2.0c
& $hdc -s 127.0.0.1:8711 start
& $hdc -s 127.0.0.1:8711 tconn <BOARD_IP>:8710
& $hdc -s 127.0.0.1:8711 -t <BOARD_IP>:8710 shell "echo ok; echo __RC=$?"
# or: .\board-check.ps1 -Target <BOARD_IP>:8710 -Hdc $hdc -ServerPort 8711
```

Qemu-ide on the same machine as the host server: always use **8711** for the host server so it does not collide with device **8710**. See `IDE-CONTRACT.md`.
