// Host regression check against the patched SAL library, not an OHOS runtime test.
#include <rtl/math.h>

#include <cstdio>
#include <string>
#include <vector>

int main()
{
    // Exceed the 256-character stack buffer and check the parsed-position map.
    const std::string narrow = "1.5" + std::string(600, '0') + "tail";
    rtl_math_ConversionStatus status = rtl_math_ConversionStatus_OutOfRange;
    const char* narrowEnd = nullptr;
    const double narrowValue = rtl_math_stringToDouble(narrow.data(),
        narrow.data() + narrow.size(), '.', ',', &status, &narrowEnd);
    if (narrowValue != 1.5 || status != rtl_math_ConversionStatus_Ok ||
        narrowEnd != narrow.data() + narrow.size() - 4)
    {
        std::fprintf(stderr, "Long narrow number conversion failed\n");
        return 1;
    }

    const std::vector<sal_Unicode> wide(narrow.begin(), narrow.end());
    const sal_Unicode* wideEnd = nullptr;
    const double wideValue = rtl_math_uStringToDouble(wide.data(),
        wide.data() + wide.size(), u'.', u',', &status, &wideEnd);
    if (wideValue != 1.5 || status != rtl_math_ConversionStatus_Ok ||
        wideEnd != wide.data() + wide.size() - 4)
    {
        std::fprintf(stderr, "Long UTF-16 number conversion failed\n");
        return 1;
    }
    std::puts("PASS: long narrow/UTF-16 numbers preserve value, status and parsed end");
    return 0;
}
