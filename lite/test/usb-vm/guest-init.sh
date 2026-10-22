#!/bin/sh
# PID1 inside QEMU guest: configfs gadget + FunctionFS + hdcd (-u) + host hdc over dummy_hcd.
export PATH=/bin:/sbin:/usr/bin HOME=/root
mount -t proc proc /proc; mount -t sysfs sys /sys; mount -t devtmpfs dev /dev
ip link set lo up
mkdir -p /tmp /data /root /dev/usb-ffs/hdc; mount -t tmpfs tmp /tmp
echo "=== guest $(uname -r) ==="
for m in usb-common usbcore udc-core configfs libcomposite usb_f_fs dummy_hcd; do
  insmod /mods/$m.ko || echo "[FAIL] insmod $m"; done
mount -t configfs none /sys/kernel/config
G=/sys/kernel/config/usb_gadget/hdc
mkdir -p $G/strings/0x409 $G/configs/b.1/strings/0x409 $G/functions/ffs.hdc
echo 0x12d1 > $G/idVendor   # PLACEHOLDER VID (emulation only)
echo 0x5000 > $G/idProduct  # PLACEHOLDER PID (emulation only)
echo 0x0200 > $G/bcdUSB
echo LA64EMU0001 > $G/strings/0x409/serialnumber
echo OHJS > $G/strings/0x409/manufacturer
echo "HDC Device (emu)" > $G/strings/0x409/product
echo hdc > $G/configs/b.1/strings/0x409/configuration
ln -s $G/functions/ffs.hdc $G/configs/b.1/
mount -t functionfs hdc /dev/usb-ffs/hdc && echo "[PASS] functionfs mounted"
echo "udc: $(ls /sys/class/udc)"
HDCD_PARAM_const_security_developermode_state=true HDCD_PARAM_const_hdc_secure=0 \
HDCD_PARAM_const_debuggable=1 HDCD_PARAM_persist_hdc_root=1 HDCD_PARAM_persist_hdc_mode=usb \
HDC_OSAL_USB_GADGET=$G /bin/hdcd -u -l4 > /tmp/hdcd.log 2>&1 &
sleep 4
echo "UDC bound: '$(cat $G/UDC)'"; ls /dev/usb-ffs/hdc
for d in /sys/bus/usb/devices/*; do [ -f $d/idVendor ] && echo "usbdev $(basename $d) $(cat $d/idVendor):$(cat $d/idProduct) '$(cat $d/product 2>/dev/null)' serial=$(cat $d/serial 2>/dev/null)"; done
/run-tests.sh
echo "=== hdcd log (usb) ==="; grep -E "HdcDaemonUSB init|control\(EP0\)|usb-ffs ready|New bulk|SetParameter|hdc_osal_usb" /tmp/hdcd.log | head; echo "=== hdcd log (tail) ==="; tail -8 /tmp/hdcd.log
echo "=== guest done ==="
poweroff -f
