# 上板检查单 — hdcd Lite（2026-10-29 包）

> 协议 **Ver 3.2.0c**，默认端口 **8710**。
> 二进制 tip：`c143133ecac36aad301b7694217e253504bfb233`
> sha256：`a9c3073713b9b389fca22898c2014890500a924cd6cc1d2a0b502f4520fe4110`
> 先校验：`sha256sum -c SHA256SUMS`（期望全部 `OK`）

> **推荐：** 板上首次手工放好 hdcd（README「Step 0」）后，在 Windows 上运行 `board-check.ps1 -Target <板IP>`，即自动完成本单 §3、§6（U1–U8）、§6b、§6c、§7 及 ACE/jerry 库回收，并生成 `board-results-<时间戳>.zip`；回传该 zip 即可替代手工粘贴。以下手工步骤保留作对照。

## 0. 准备

- [ ] 板子网络可达，记录 IP：`____________`
- [ ] 主机 hdc 为 6.1-LTS：`hdc -v` → `Ver: 3.2.0c`
- [ ] 包内文件齐全（对照 `MANIFEST`）

## 1. 推送文件

| 本地 | 板上 |
|---|---|
| `hdcd.stripped` | `/data/hdcd/hdcd`（`chmod +x`） |
| `etc/hdcd.para` | `/etc/hdcd/hdcd.para` |

```sh
mkdir -p /etc/hdcd /data/hdcd /tmp/ohjs
cp hdcd.stripped /data/hdcd/hdcd && chmod +x /data/hdcd/hdcd
cp etc/hdcd.para /etc/hdcd/hdcd.para
```

## 2. 板上启动（TCP）

```sh
/data/hdcd/hdcd -v                 # 期望: Ver: 3.2.0c
/data/hdcd/hdcd -t -l4 > /tmp/hdcd.log 2>&1 &
sleep 2; grep 'TCP listen on port' /tmp/hdcd.log   # 期望: TCP listen on port:[8710]
netstat -ltn 2>/dev/null | grep 8710 || ss -ltn | grep 8710
```

失败先看：`/tmp/hdcd.log` 是否有 `non developer mode`、`TCP/USB disable`。

## 3. 主机联调（TCP）

```bash
hdc tconn <板IP>:8710                      # 期望: Connect OK
hdc list targets -v                        # 期望: <板IP>:8710  TCP  Connected
hdc -t <板IP>:8710 shell 'echo ok; uname -m'   # 期望: ok / loongarch64
dd if=/dev/urandom of=big.bin bs=1M count=20
hdc -t <板IP>:8710 file send big.bin /tmp/ohjs/big.bin
hdc -t <板IP>:8710 file recv /tmp/ohjs/big.bin big.back && cmp big.bin big.back && echo CMP_OK
hdc -t <板IP>:8710 fport tcp:19001 tcp:5001 && hdc -t <板IP>:8710 fport ls
hdc -t <板IP>:8710 fport rm tcp:19001 tcp:5001
hdc -t <板IP>:8710 shell 'false; echo __RC=$?'   # 期望 __RC=1（退出码靠标记）
```

- [ ] tconn  [ ] shell  [ ] file cmp  [ ] fport  [ ] __RC 标记

## 4. tmode 换端口（可选）

```bash
hdc -t <板IP>:8710 tmode port 8755
sleep 3; hdc tconn <板IP>:8755 && hdc -t <板IP>:8755 shell echo ok
```

- [ ] 新端口可连  [ ] 旧 8710 不再服务

## 5. 常见失败（TCP）

| 现象 | 原因 |
|---|---|
| non developer mode | para 缺 `const.security.developermode.state=true` |
| Unauthorized | `const.hdc.secure` 未设 0 |
| Connect failed | 未监听 / 防火墙 / IP |
| 握手失败 | 主机 hdc 非 6.1-LTS（Ver 3.2.0c） |
| tmode 端口不变 | 非本包 OSAL re-exec 二进制 |

## 6. USB 自检（只读检查，不建 gadget）

逐条在板上执行并保留输出。命令均为 busybox/toybox 可用的写法。

| # | 命令 | 期望 |
|---|---|---|
| U1 | `uname -a` | 含 `6.6` 与 `loongarch64` |
| U2 | `ls /sys/class/udc` | 至少一个 UDC 名（如 `xxxx.usb`/`dwc2`/`dwc3`）；为空或目录不存在 = 无 device 控制器或驱动未加载/未处于 OTG device 模式 |
| U3 | 内核配置（见下方脚本） | `CONFIG_USB_GADGET`、`CONFIG_USB_CONFIGFS`、`CONFIG_USB_CONFIGFS_F_FS`、`CONFIG_USB_FUNCTIONFS`、`CONFIG_CONFIGFS_FS` 均为 `=y` 或 `=m`；其中 `CONFIG_USB_FUNCTIONFS` 可为未设（只要 `CONFIG_USB_CONFIGFS_F_FS` 为 y/m 即可） |
| U4 | `mount \| grep -E 'configfs\|functionfs'` | `configfs on /sys/kernel/config type configfs`；若已有 hdc 函数：`... type functionfs`。无输出 = 尚未挂载（可接受，记录） |
| U5 | `ls /sys/kernel/config/usb_gadget` | 目录存在（可为空，或列出已有 gadget）。`No such file` = configfs 未挂载或 `CONFIG_USB_CONFIGFS` 未开 |
| U6 | 可写目录（见下方脚本） | `/data` `/tmp` 为 `WRITABLE`；`/etc` 若 `RO` 则需把 para 放可写处并设 `HDC_OSAL_DEFAULT_PARA` |
| U7 | `cat /proc/filesystems \| grep -E 'configfs\|functionfs'` | `nodev configfs` 与 `nodev functionfs`（模块未加载时可能缺，配合 U3/U8） |
| U8 | `lsmod 2>/dev/null \| grep -E 'usb_f_fs\|libcomposite\|configfs'; ls /lib/modules/$(uname -r) 2>/dev/null \| head` | 若 U3 为 `=m`：能看到已加载模块或模块目录 |

U3 内核配置检查（自动回退）：

```sh
K="CONFIG_USB_GADGET CONFIG_USB_CONFIGFS CONFIG_USB_CONFIGFS_F_FS CONFIG_USB_FUNCTIONFS CONFIG_CONFIGFS_FS"
if [ -r /proc/config.gz ]; then SRC=/proc/config.gz; CAT="zcat /proc/config.gz"
elif [ -r /boot/config-$(uname -r) ]; then SRC=/boot/config-$(uname -r); CAT="cat $SRC"
elif ls /boot/config-* >/dev/null 2>&1; then SRC=$(ls /boot/config-* | head -1); CAT="cat $SRC"
else SRC=none; fi
echo "config source: $SRC"
if [ "$SRC" != none ]; then
  for k in $K; do v=$($CAT | grep -E "^$k=|^# $k is not set"); echo "$k -> ${v:-ABSENT}"; done
else
  echo "NO CONFIG: fallback checks"
  grep -E 'configfs|functionfs' /proc/filesystems
  ls -d /sys/kernel/config /sys/class/udc /sys/module/libcomposite /sys/module/usb_f_fs 2>&1
fi
```

期望（示例）：

```
config source: /proc/config.gz
CONFIG_USB_GADGET -> CONFIG_USB_GADGET=y
CONFIG_USB_CONFIGFS -> CONFIG_USB_CONFIGFS=y
CONFIG_USB_CONFIGFS_F_FS -> CONFIG_USB_CONFIGFS_F_FS=y
CONFIG_USB_FUNCTIONFS -> CONFIG_USB_FUNCTIONFS=y    (或 ABSENT / is not set，可接受)
CONFIG_CONFIGFS_FS -> CONFIG_CONFIGFS_FS=y
```

无配置文件时（`NO CONFIG`）：期望 `/proc/filesystems` 出现 `configfs` 与 `functionfs`，且 `/sys/kernel/config`、`/sys/class/udc` 存在。

U6 可写目录检查：

```sh
for d in /data /data/hdcd /tmp /etc /etc/hdcd; do
  mkdir -p "$d" 2>/dev/null
  if touch "$d/.hdcd_w" 2>/dev/null; then rm -f "$d/.hdcd_w"; echo "$d WRITABLE"; else echo "$d RO_OR_MISSING"; fi
done
df -h /data /tmp /etc 2>/dev/null
```

期望：`/data WRITABLE`、`/data/hdcd WRITABLE`、`/tmp WRITABLE`；`/etc`、`/etc/hdcd` 任一结果均记录。

> 判定：U2 非空 且 U3 五项满足（或 NO CONFIG 回退通过）→ 可进入 USB 上板（下一包提供 gadget 建立脚本，VID/PID 待定，仿真用的 0x12d1:0x5000 仅为占位）。


## 6b. 调试固件判定（bm set）

| # | 命令 | 期望 / 判定 |
|---|---|---|
| B1 | `bm set -s disable; echo __RC=$?` | 输出含 `success` → **debug 固件**（`OHOS_DEBUG`，可关签名校验），之后安装未签名 hap 可行。输出 `fail` → debug 固件但 BMS 拒绝/未起。输出为整段 usage / `error command!` / `wrong param`（无 `success`）→ **release 固件**（`set` 子命令被 `#ifdef OHOS_DEBUG` 裁掉），只能装正式签名 hap。`__RC` 恒为 0，不作判定依据 |
| B2 | `bm set -d enable` | 同上判定（debug 签名模式），可选 |

## 6c. hilogcat 与 apphilogcat 争用 /dev/hilog

目的：确认 /dev/hilog 读取是否"消费式"（两个读者分走日志）。决定 IDE 用 `hilogcat` 流还是读 `/storage/data/log/hilog*.txt`。

```sh
ps -ef 2>/dev/null | grep -E '[a]pphilogcat|[h]ilogcat' || ps | grep -E '[a]pphilogcat|[h]ilogcat'
ls -l /dev/hilog /storage/data/log/ 2>&1
hilogcat > /tmp/ohjs/hilog.cap 2>&1 &
echo $! > /tmp/ohjs/hilogcat.pid
M=OHJSPROBE$(date +%s)
aa start -p $M -n ProbeAbility        # 不存在的 bundle → AMS/BMS 打出含 $M 的错误日志（若无该行，见下方备选）
sleep 3
kill $(cat /tmp/ohjs/hilogcat.pid)
echo "marker=$M"
echo "cap:  $(grep -c "$M" /tmp/ohjs/hilog.cap)"
echo "file: $(cat /storage/data/log/hilog*.txt 2>/dev/null | grep -c "$M")"
echo "cap lines: $(wc -l < /tmp/ohjs/hilog.cap)"; tail -5 /tmp/ohjs/hilog.cap
tail -5 /storage/data/log/hilog1.txt /storage/data/log/hilog2.txt 2>&1
```

期望与判定：

| 现象 | 结论 / IDE 方案 |
|---|---|
| apphilogcat 未运行（ps 无输出） | 无争用；IDE 用 `hdc shell hilogcat` 流 |
| apphilogcat 运行，`cap ≥1` 且 `file ≥1` | 广播式（各读者都收到）；IDE 用 hilogcat 流 |
| apphilogcat 运行，只有一边 ≥1（另一边 0） | **消费式争用**；IDE 改为 `tail -f /storage/data/log/hilog1.txt`（或停 apphilogcat 再用 hilogcat） |
| 两边都 0 | 标记行未产生：改用备选——观察 10 s 内两边的末尾 5 行时间戳是否交错缺失（同一时刻只在一边出现 = 消费式） |

注：`file` 写入有缓冲（apphilogcat 定期 flush），若 `file=0` 先 `sleep 10` 再查一次。

## 7. 回传（请整段粘贴）

请在板上执行下面一段，将**全部输出**连同第 3 节主机侧输出原样贴回：

```sh
echo "== pkg"; sha256sum /data/hdcd/hdcd; /data/hdcd/hdcd -v
echo "== U1"; uname -a
echo "== U2"; ls -l /sys/class/udc 2>&1
echo "== U3"; # 粘贴上方 U3 脚本输出
echo "== U4"; mount | grep -E 'configfs|functionfs'
echo "== U5"; ls -l /sys/kernel/config/usb_gadget 2>&1
echo "== U6"; # 粘贴上方 U6 脚本输出
echo "== U7"; grep -E 'configfs|functionfs' /proc/filesystems
echo "== U8"; lsmod 2>/dev/null | grep -E 'usb_f_fs|libcomposite|configfs'
echo "== B1"; bm set -s disable; echo __RC=$?
echo "== H1"; # 粘贴 6c 整段输出
echo "== tools"; which sh bm aa hilogcat 2>&1
echo "== hdcd log"; tail -50 /tmp/hdcd.log
echo "== persist"; cat /data/hdcd/persist.para 2>&1
```

附：主机 `hdc -v`、`hdc list targets -v`、第 3 节各命令输出。
