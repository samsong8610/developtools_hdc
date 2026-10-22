#!/bin/bash
# Build initramfs (busybox + Debian 6.12 gadget modules + native hdcd + host hdc) and boot QEMU/KVM.
set -euo pipefail
W=/workspace/hdcd-port; V=$W/b/vm; D=$(cd "$(dirname "$0")" && pwd)
KV=6.12.113+deb13-amd64; K=$V/kroot/usr/lib/modules/$KV/kernel
HDCD=${HDCD:-$W/b/native/out/hdcd.stripped}; HDC=$(readlink -f $W/hdc-host)
R=$V/rootfs; rm -rf $R; mkdir -p $R/{bin,sbin,proc,sys,dev,mods,lib64,lib/x86_64-linux-gnu,etc}
cp /bin/busybox $R/bin/; for a in $($R/bin/busybox --list); do [ -e $R/bin/$a ] || ln -s busybox $R/bin/$a; done
for m in usb-common usbcore udc-core configfs libcomposite usb_f_fs dummy_hcd; do
  xz -dc $(find $K -name "$m.ko.xz") > $R/mods/$m.ko; done
cp $HDCD $R/bin/hdcd; cp $HDC $R/bin/hdc
for l in $(ldd $HDC | grep -o '/[^ ]*'); do cp -L $l $R$l 2>/dev/null || { mkdir -p $R$(dirname $l); cp -L $l $R$l; }; done
echo 'root:x:0:0::/root:/bin/sh' > $R/etc/passwd; echo 'root:x:0:' > $R/etc/group
cp $D/guest-init.sh $R/init; cp $D/run-tests.sh $R/run-tests.sh; chmod +x $R/init $R/run-tests.sh
(cd $R && find . | cpio -o -H newc --quiet | gzip -1) > $V/initramfs.gz
# KVM on this box hangs at boot (nested virt); TCG is used. Set ACC=-enable-kvm to try.
ACC=${ACC:-}
timeout 600 qemu-system-x86_64 $ACC -m 1024 -smp 2 -nographic -no-reboot \
  -kernel $V/kroot/boot/vmlinuz-$KV -initrd $V/initramfs.gz -append "console=ttyS0 quiet loglevel=3 panic=-1"
