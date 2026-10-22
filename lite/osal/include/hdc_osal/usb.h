/*
 * Copyright (C) 2026 Sam Song
 * Licensed under the Apache License, Version 2.0
 *
 * USB FunctionFS path configuration for lite Linux gadget.
 */
#ifndef HDC_OSAL_USB_H
#define HDC_OSAL_USB_H

#ifdef __cplusplus
extern "C" {
#endif

/* Default: /dev/usb-ffs/  (trailing slash kept for path join) */
void hdc_osal_usb_set_ffs_base(const char *base);
const char *hdc_osal_usb_get_ffs_base(void);

/*
 * Lite replacement for OH init's "sys.usb.ffs.ready" trigger: once hdcd has
 * written FunctionFS descriptors to ep0, bind the configfs gadget to a UDC.
 * Gadget dir: env HDC_OSAL_USB_GADGET or param const.hdc.usb.gadget
 *             (e.g. /sys/kernel/config/usb_gadget/hdc). Unset => no-op
 *             (board init script binds UDC itself).
 * UDC name:   env HDC_OSAL_USB_UDC or param const.hdc.usb.udc; empty =>
 *             first entry of /sys/class/udc.
 * Returns 0 on success/no-op, -1 on error.
 */
int hdc_osal_usb_on_ffs_ready(void);

#ifdef __cplusplus
}
#endif

#endif /* HDC_OSAL_USB_H */
