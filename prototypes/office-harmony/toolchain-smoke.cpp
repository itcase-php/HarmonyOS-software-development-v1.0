#include <atomic>
#include <string>
#include <thread>

// Toolchain/ABI probe only. This exports no document conversion capability.
extern "C" int hdm_office_toolchain_smoke() {
    std::atomic<int> value{0};
    std::thread worker([&value] { value.store(26); });
    worker.join();
    const std::string text="OHOS";
    return value.load()==26 && text.size()==4 ? 26 : -1;
}
