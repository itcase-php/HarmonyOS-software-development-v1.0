#pragma once
#include <array>
#include <cstddef>
#include <cstdint>
#include <string>

namespace hdm::production {
class Sha256 final {
public:
    Sha256();
    void Update(const void* data, std::size_t size);
    std::string FinalHex();
private:
    void Block(const std::uint8_t* data);
    std::array<std::uint32_t, 8> state_{};
    std::array<std::uint8_t, 64> buffer_{};
    std::uint64_t bytes_{};
    std::size_t buffered_{};
    bool finalized_{};
};
} // namespace hdm::production
