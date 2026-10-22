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

#ifdef __cplusplus
}
#endif

#endif /* HDC_OSAL_USB_H */
