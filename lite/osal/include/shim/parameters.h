/* Shim: OpenHarmony parameters.h → OHOS::system::GetParameter */
#ifndef HDC_OSAL_SHIM_PARAMETERS_H
#define HDC_OSAL_SHIM_PARAMETERS_H
#include "hdc_osal/param.h"
#include <string>
namespace OHOS {
namespace system {
inline std::string GetParameter(const char *key, const char *def)
{
    char buf[512] = {0};
    int n = ::GetParameter(key, def, buf, sizeof(buf));
    if (n <= 0) {
        return def ? std::string(def) : std::string();
    }
    return std::string(buf);
}
} /* namespace system */
} /* namespace OHOS */
#endif
