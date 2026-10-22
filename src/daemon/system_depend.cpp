/*
 * Copyright (C) 2021 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
/*
############
This file is used to support compatibility between platforms, differences between old and new projects and
compilation platforms

defined HARMONY_PROJECT
With openharmony toolchains support. If not defined, it should be [device]buildroot or [PC]msys64(...)/ubuntu-apt(...)
envirments
############
*/
#include "system_depend.h"
#include "base.h"
#if defined(HARMONY_PROJECT) || defined(HDC_LITE_OSAL)
extern "C" {
#include "init_reboot.h"
#include "parameter.h"
}
#endif

namespace Hdc {
namespace SystemDepend {
bool SetDevItem(const char *key, const char *value)
{
    bool ret = true;
#if defined(HARMONY_PROJECT) || defined(HDC_LITE_OSAL)
    ret = SetParameter(key, value) == 0;
#else
    char outBuf[256] = "";
    string stringBuf = Base::StringFormat("param set %s %s", key, value);
    Base::RunPipeComand(stringBuf.c_str(), outBuf, sizeof(outBuf), true);
#endif  // HARMONY_PROJECT || HDC_LITE_OSAL
    return ret;
}

bool GetDevItem(const char *key, string &out, const char *preDefine)
{
    bool ret = true;
    char tmpStringBuf[BUF_SIZE_MEDIUM] = "";
#if defined(HARMONY_PROJECT) || defined(HDC_LITE_OSAL)
    auto res = GetParameter(key, preDefine, tmpStringBuf, BUF_SIZE_MEDIUM);
    if (res <= 0) {
        return false;
    }
#endif
    out = tmpStringBuf;
    return ret;
}

uint32_t GetDevUint(const char *key, uint32_t defaultValue)
{
    return GetUintParameter(key, defaultValue);
}

bool CallDoReboot(const char *reason)
{
    string rebootCtrl = "ohos.startup.powerctrl";
#if defined(HDC_LITE_OSAL)
    /* Lite: map to OSAL reboot (also records reason via param for init scripts). */
    SetDevItem(rebootCtrl.c_str(), reason);
    return DoReboot(reason) == 0;
#elif defined(HARMONY_PROJECT)
    return SetDevItem(rebootCtrl.c_str(), reason);
#else
    return false;
#endif
}

bool RebootDevice(const string &cmd)
{
    string reason = "reboot";
    if (cmd != "") {
        reason += ",";
        reason += cmd;
    }
    WRITE_LOG(LOG_DEBUG, "DoReboot with args:[%s] for cmd:[%s]", reason.c_str(), cmd.c_str());
    return CallDoReboot(reason.c_str());
}
}
}  // namespace Hdc
